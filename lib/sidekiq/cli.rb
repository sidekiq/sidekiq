trap 'INT' do
  # Handle Ctrl-C in JRuby like MRI
  # http://jira.codehaus.org/browse/JRUBY-4637
  Thread.main.raise Interrupt
end

trap 'TERM' do
  # Heroku sends TERM and then waits 10 seconds for process to exit.
  Thread.main.raise Interrupt
end

require 'optparse'
require 'sidekiq/version'
require 'sidekiq/util'
require 'sidekiq/redis_connection'
require 'sidekiq/manager'

module Sidekiq
  class CLI
    include Util

    # Used for CLI testing
    attr_accessor :options, :code

    def initialize
      @code = nil
    end

    def parse(args=ARGV)
      Sidekiq::Util.logger

      @options = {
        :queues => [],
        :concurrency => 25,
        :require => '.',
        :environment => nil,
      }
      cli = parse_options(args)
      config = parse_config(cli)
      @options.merge!(config.merge(cli))

      set_logger_level_to_debug if @options[:verbose]

      write_pid
      validate!
      boot_system
    end

    def run
      Sidekiq.redis = RedisConnection.create(:url => @options[:server], :namespace => @options[:namespace])
      manager = Sidekiq::Manager.new(@options)
      begin
        logger.info 'Starting processing, hit Ctrl-C to stop'
        manager.start!
        # HACK need to determine how to pause main thread while
        # waiting for signals.
        sleep
      rescue Interrupt
        # TODO Need clean shutdown support from Celluloid
        logger.info 'Shutting down, pausing 5 seconds to let workers finish...'
        manager.stop!
        manager.wait(:shutdown)
      end
    end

    private

    def die(code)
      exit(code)
    end

    def detected_environment
      @options[:environment] ||= ENV['RAILS_ENV'] || ENV['RACK_ENV'] || 'development'
    end

    def boot_system
      ENV['RACK_ENV'] = ENV['RAILS_ENV'] = detected_environment

      raise ArgumentError, "#{@options[:require]} does not exist" unless File.exist?(@options[:require])

      if File.directory?(@options[:require])
        require File.expand_path("#{@options[:require]}/config/environment.rb")
        ::Rails.application.eager_load!
      else
        require @options[:require]
      end
    end

    def validate!
      @options[:queues] << 'default' if @options[:queues].empty?
      @options[:queues].shuffle!

      if !File.exist?(@options[:require]) ||
         (File.directory?(@options[:require]) && !File.exist?("#{@options[:require]}/config/application.rb"))
        logger.info "=================================================================="
        logger.info "  Please point sidekiq to a Rails 3 application or a Ruby file    "
        logger.info "  to load your worker classes with -r [DIR|FILE]."
        logger.info "=================================================================="
        logger.info @parser
        die(1)
      end
    end

    def parse_options(argv)
      opts = {}

      @parser = OptionParser.new do |o|
        o.on "-q", "--queue QUEUE,WEIGHT", "Queue to process, with optional weight" do |arg|
          (q, weight) = arg.split(",")
          parse_queues(q, weight)
        end

        o.on "-v", "--verbose", "Print more verbose output" do
          set_logger_level_to_debug
        end

        o.on "-n", "--namespace NAMESPACE", "namespace worker queues are under" do |arg|
          opts[:namespace] = arg
        end

        o.on "-s", "--server LOCATION", "Where to find Redis" do |arg|
          opts[:server] = arg
        end

        o.on '-e', '--environment ENV', "Application environment" do |arg|
          opts[:environment] = arg
        end

        o.on '-r', '--require [PATH|DIR]', "Location of Rails application with workers or file to require" do |arg|
          opts[:require] = arg
        end

        o.on '-c', '--concurrency INT', "processor threads to use" do |arg|
          opts[:concurrency] = arg.to_i
        end

        o.on '-P', '--pidfile PATH', "path to pidfile" do |arg|
          opts[:pidfile] = arg
        end

        o.on '-C', '--config PATH', "path to YAML config file" do |arg|
          opts[:config_file] = arg
        end
      end

      @parser.banner = "sidekiq [options]"
      @parser.on_tail "-h", "--help", "Show help" do
        logger.info @parser
        die 1
      end
      @parser.parse!(argv)
      opts
    end

    def write_pid
      if path = @options[:pidfile]
        File.open(path, 'w') do |f|
          f.puts Process.pid
        end
      end
    end

    def parse_config(cli)
      opts = {}
      if cli[:config_file] && File.exist?(cli[:config_file])
        require 'yaml'
        opts = YAML.load_file cli[:config_file]
        queues = opts.delete(:queues) || []
        if @options[:queues].empty?
          queues.each { |pair| parse_queues(*pair) }
        end
      end
      opts
    end

    def parse_queues(q, weight)
      (weight || 1).to_i.times do
        @options[:queues] << q
      end
    end

    def set_logger_level_to_debug
      Sidekiq::Util.logger.level = Logger::DEBUG
    end

  end
end
