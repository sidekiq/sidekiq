require 'optparse'
require 'sidekiq'
require 'sidekiq/server'

module Sidekiq
  class CLI
    include Util

    def initialize
      parse_options
      validate!
      boot_rails
    end

    def run
      write_pid if @options[:daemon]

      server = Sidekiq::Server.new(@options[:server], @options)
      begin
        log 'Starting processing, hit Ctrl-C to stop'
        server.start!
        sleep 1000
      rescue Interrupt
        log 'Shutting down...'
        server.stop!
        server.wait(:shutdown)
      end
    end

    private

    def boot_rails
      #APP_PATH = File.expand_path('config/application.rb')
      ENV['RAILS_ENV'] = 'production'
      require File.expand_path("#{@options[:rails]}/config/environment.rb")
      Rails.application.config.threadsafe!
    end

    def validate!
      $DEBUG = @options[:verbose]
      if @options[:queues].size == 0
        log "========== Please configure at least one queue to process =========="
        log @parser
        exit(1)
      end

      if !File.exist?("#{@options[:rails]}/config/boot.rb")
        log "========== Please point sidekiq to a Rails 3 application =========="
        log @parser
        exit(1)
      end
    end

    def parse_options(argv=ARGV)
      @options = {
        :daemon => false,
        :verbose => false,
        :queues => [],
        :worker_count => 25,
        :server => 'redis://localhost:6379/0',
        :pidfile => nil,
        :rails => '.',
      }

      @parser = OptionParser.new do |o|
        o.on "-q", "--queue QUEUE,WEIGHT", "Queue to process, with optional weight" do |arg|
          (q, weight) = arg.split(",")
          (weight || 1).times do
            @options[:queues] << q
          end
        end

        o.on "-d", "Daemonize" do |arg|
          @options[:daemon] = arg
        end

        o.on "--pidfile PATH", "Use PATH as a pidfile" do |arg|
          @options[:pidfile] = arg
        end

        o.on "-v", "--verbose", "Print more verbose output" do
          @options[:verbose] = true
        end

        o.on "-s", "--server LOCATION", "Where to find the server" do |arg|
          @options[:server] = arg
        end

        o.on '-r', '--rails PATH', "Rails application with workers" do |arg|
          @options[:rails] = arg
        end

        o.on '-c', '--concurrency INT', "Worker threads to use" do |arg|
          @options[:worker_count] = arg.to_i
        end
      end

      @parser.banner = "sidekiq -q foo -q bar <more options>"
      @parser.on_tail "-h", "--help", "Show help" do
        log @parser
        exit 1
      end
      @parser.parse!(argv)
    end

    def write_pid
      if path = @options[:pidfile]
        File.open(path, "w") do |f|
          f.puts Process.pid
        end
      end
    end

  end
end
