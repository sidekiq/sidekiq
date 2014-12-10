# encoding: utf-8
$stdout.sync = true

require 'yaml'
require 'singleton'
require 'optparse'
require 'erb'
require 'fileutils'

require 'sidekiq'
require 'sidekiq/util'

module Sidekiq
  # We are shutting down Sidekiq but what about workers that
  # are working on some long job?  This error is
  # raised in workers that have not finished within the hard
  # timeout limit.  This is needed to rollback db transactions,
  # otherwise Ruby's Thread#kill will commit.  See #377.
  # DO NOT RESCUE THIS ERROR.
  class Shutdown < Interrupt; end

  class CLI
    include Util
    include Singleton unless $TESTING

    # Used for CLI testing
    attr_accessor :code
    attr_accessor :launcher
    attr_accessor :environment

    def initialize
      @code = nil
    end

    def parse(args=ARGV)
      @code = nil

      setup_options(args)
      initialize_logger
      validate!
      daemonize
      write_pid
      load_celluloid
    end

    # Code within this method is not tested because it alters
    # global process state irreversibly.  PRs which improve the
    # test coverage of Sidekiq::CLI are welcomed.
    def run
      boot_system
      print_banner

      self_read, self_write = IO.pipe

      %w(INT TERM USR1 USR2 TTIN).each do |sig|
        begin
          trap sig do
            self_write.puts(sig)
          end
        rescue ArgumentError
          puts "Signal #{sig} not supported"
        end
      end

      logger.info "Running in #{RUBY_DESCRIPTION}"
      logger.info Sidekiq::LICENSE
      logger.info "Upgrade to Sidekiq Pro for more features and support: http://sidekiq.org/pro" unless defined?(::Sidekiq::Pro)

      fire_event(:startup)

      if !options[:daemon]
        logger.info 'Starting processing, hit Ctrl-C to stop'
      end

      require 'sidekiq/launcher'
      @launcher = Sidekiq::Launcher.new(options)

      begin
        launcher.run

        while readable_io = IO.select([self_read])
          signal = readable_io.first[0].gets.strip
          handle_signal(signal)
        end
      rescue Interrupt
        logger.info 'Shutting down'
        launcher.stop
        fire_event(:shutdown)
        # Explicitly exit so busy Processor threads can't block
        # process shutdown.
        exit(0)
      end
    end

    def self.banner
%q{         s
          ss
     sss  sss         ss
     s  sss s   ssss sss   ____  _     _      _    _
     s     sssss ssss     / ___|(_) __| | ___| | _(_) __ _
    s         sss         \___ \| |/ _` |/ _ \ |/ / |/ _` |
    s sssss  s             ___) | | (_| |  __/   <| | (_| |
    ss    s  s            |____/|_|\__,_|\___|_|\_\_|\__, |
    s     s s                                           |_|
          s s
         sss
         sss }
    end

    def handle_signal(sig)
      Sidekiq.logger.debug "Got #{sig} signal"
      case sig
      when 'INT'
        # Handle Ctrl-C in JRuby like MRI
        # http://jira.codehaus.org/browse/JRUBY-4637
        raise Interrupt
      when 'TERM'
        # Heroku sends TERM and then waits 10 seconds for process to exit.
        raise Interrupt
      when 'USR1'
        Sidekiq.logger.info "Received USR1, no longer accepting new work"
        launcher.manager.async.stop
        fire_event(:quiet)
      when 'USR2'
        if Sidekiq.options[:logfile]
          Sidekiq.logger.info "Received USR2, reopening log file"
          Sidekiq::Logging.reopen_logs
        end
      when 'TTIN'
        Thread.list.each do |thread|
          Sidekiq.logger.warn "Thread TID-#{thread.object_id.to_s(36)} #{thread['label']}"
          if thread.backtrace
            Sidekiq.logger.warn thread.backtrace.join("\n")
          else
            Sidekiq.logger.warn "<no backtrace available>"
          end
        end
      end
    end

    private

    def print_banner
      # Print logo and banner for development
      if environment == 'development' && $stdout.tty?
        puts "\e[#{31}m"
        puts Sidekiq::CLI.banner
        puts "\e[0m"
      end
    end

    def load_celluloid
      raise "Celluloid cannot be required until here, or it will break Sidekiq's daemonization" if defined?(::Celluloid) && options[:daemon]

      # Celluloid can't be loaded until after we've daemonized
      # because it spins up threads and creates locks which get
      # into a very bad state if forked.
      require 'celluloid/autostart'
      Celluloid.logger = (options[:verbose] ? Sidekiq.logger : nil)

      require 'sidekiq/manager'
      require 'sidekiq/scheduled'
    end

    def daemonize
      return unless options[:daemon]

      raise ArgumentError, "You really should set a logfile if you're going to daemonize" unless options[:logfile]
      files_to_reopen = []
      ObjectSpace.each_object(File) do |file|
        files_to_reopen << file unless file.closed?
      end

      ::Process.daemon(true, true)

      files_to_reopen.each do |file|
        begin
          file.reopen file.path, "a+"
          file.sync = true
        rescue ::Exception
        end
      end

      [$stdout, $stderr].each do |io|
        File.open(options[:logfile], 'ab') do |f|
          io.reopen(f)
        end
        io.sync = true
      end
      $stdin.reopen('/dev/null')

      initialize_logger
    end

    def set_environment(cli_env)
      @environment = cli_env || ENV['RAILS_ENV'] || ENV['RACK_ENV'] || 'development'
    end

    alias_method :die, :exit
    alias_method :☠, :exit

    def setup_options(args)
      opts = parse_options(args)
      set_environment opts[:environment]

      cfile = opts[:config_file]
      opts = parse_config(cfile).merge(opts) if cfile

      opts[:strict] = true if opts[:strict].nil?

      options.merge!(opts)
    end

    def options
      Sidekiq.options
    end

    def boot_system
      ENV['RACK_ENV'] = ENV['RAILS_ENV'] = environment

      raise ArgumentError, "#{options[:require]} does not exist" unless File.exist?(options[:require])

      if File.directory?(options[:require])
        require 'rails'
        if ::Rails::VERSION::MAJOR < 4
          require 'sidekiq/rails'
          require File.expand_path("#{options[:require]}/config/environment.rb")
          ::Rails.application.eager_load!
        else
          # Painful contortions, see 1791 for discussion
          require File.expand_path("#{options[:require]}/config/application.rb")
          ::Rails::Application.initializer "sidekiq.eager_load" do
            ::Rails.application.config.eager_load = true
          end
          require 'sidekiq/rails'
          require File.expand_path("#{options[:require]}/config/environment.rb")
        end
        options[:tag] ||= default_tag
      else
        require options[:require]
      end
    end

    def default_tag
      dir = ::Rails.root
      name = File.basename(dir)
      if name.to_i != 0 && prevdir = File.dirname(dir) # Capistrano release directory?
        if File.basename(prevdir) == 'releases'
          return File.basename(File.dirname(prevdir))
        end
      end
      name
    end

    def validate!
      options[:queues] << 'default' if options[:queues].empty?

      if !File.exist?(options[:require]) ||
         (File.directory?(options[:require]) && !File.exist?("#{options[:require]}/config/application.rb"))
        logger.info "=================================================================="
        logger.info "  Please point sidekiq to a Rails 3/4 application or a Ruby file  "
        logger.info "  to load your worker classes with -r [DIR|FILE]."
        logger.info "=================================================================="
        logger.info @parser
        die(1)
      end
    end

    def parse_options(argv)
      opts = {}

      @parser = OptionParser.new do |o|
        o.on '-c', '--concurrency INT', "processor threads to use" do |arg|
          opts[:concurrency] = Integer(arg)
        end

        o.on '-d', '--daemon', "Daemonize process" do |arg|
          opts[:daemon] = arg
        end

        o.on '-e', '--environment ENV', "Application environment" do |arg|
          opts[:environment] = arg
        end

        o.on '-g', '--tag TAG', "Process tag for procline" do |arg|
          opts[:tag] = arg
        end

        o.on '-i', '--index INT', "unique process index on this machine" do |arg|
          opts[:index] = Integer(arg.match(/\d+/)[0])
        end

        o.on "-q", "--queue QUEUE[,WEIGHT]", "Queues to process with optional weights" do |arg|
          queue, weight = arg.split(",")
          parse_queue opts, queue, weight
        end

        o.on '-r', '--require [PATH|DIR]', "Location of Rails application with workers or file to require" do |arg|
          opts[:require] = arg
        end

        o.on '-t', '--timeout NUM', "Shutdown timeout" do |arg|
          opts[:timeout] = Integer(arg)
        end

        o.on "-v", "--verbose", "Print more verbose output" do |arg|
          opts[:verbose] = arg
        end

        o.on '-C', '--config PATH', "path to YAML config file" do |arg|
          opts[:config_file] = arg
        end

        o.on '-L', '--logfile PATH', "path to writable logfile" do |arg|
          opts[:logfile] = arg
        end

        o.on '-P', '--pidfile PATH', "path to pidfile" do |arg|
          opts[:pidfile] = arg
        end

        o.on '-V', '--version', "Print version and exit" do |arg|
          puts "Sidekiq #{Sidekiq::VERSION}"
          die(0)
        end
      end

      @parser.banner = "sidekiq [options]"
      @parser.on_tail "-h", "--help", "Show help" do
        logger.info @parser
        die 1
      end
      @parser.parse!(argv)
      opts[:config_file] ||= 'config/sidekiq.yml' if File.exist?('config/sidekiq.yml')
      opts
    end

    def initialize_logger
      Sidekiq::Logging.initialize_logger(options[:logfile]) if options[:logfile]

      Sidekiq.logger.level = ::Logger::DEBUG if options[:verbose]
    end

    def write_pid
      if path = options[:pidfile]
        pidfile = File.expand_path(path)
        File.open(pidfile, 'w') do |f|
          f.puts ::Process.pid
        end
      end
    end

    def parse_config(cfile)
      opts = {}
      if File.exist?(cfile)
        opts = YAML.load(ERB.new(IO.read(cfile)).result) || opts
        opts = opts.merge(opts.delete(environment) || {})
        parse_queues(opts, opts.delete(:queues) || [])
      else
        # allow a non-existent config file so Sidekiq
        # can be deployed by cap with just the defaults.
      end
      ns = opts.delete(:namespace)
      if ns
        # logger hasn't been initialized yet, puts is all we have.
        puts("namespace should be set in your ruby initializer, is ignored in config file")
        puts("config.redis = { :url => ..., :namespace => '#{ns}' }")
      end
      opts
    end

    def parse_queues(opts, queues_and_weights)
      queues_and_weights.each { |queue_and_weight| parse_queue(opts, *queue_and_weight) }
    end

    def parse_queue(opts, q, weight=nil)
      [weight.to_i, 1].max.times do
       (opts[:queues] ||= []) << q
      end
      opts[:strict] = false if weight.to_i > 0
    end
  end
end
