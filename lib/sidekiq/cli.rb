require 'optparse'
require 'sidekiq'

module Sidekiq
  class CLI
    def initialize
      parse_options
      validate!
      enable_rails3 if File.exist?("config/application.rb")
    end

    def run
      write_pid

      server = Sidekiq::Server.new(@options[:server], @options)
      begin
        log 'Starting processing, hit Ctrl-C to stop'
        server.run
      rescue Interrupt
        log 'Shutting down...'
        server.stop
        log '...bye!'
      end
    end

    private

    def enable_rails3
      #APP_PATH = File.expand_path('config/application.rb')
      require File.expand_path('config/boot.rb')
    end

    def log(str)
      STDOUT.puts str
    end

    def error(str)
      @STDERR.puts "ERROR: #{str}"
    end

    def validate!
      if @options[:queues].size == 0
        log "========== Please configure at least one queue to process =========="
        log @parser
      end
    end

    def parse_options(argv=ARGV)
      @options = {
        :daemon => false,
        :verbose => false,
        :queues => [],
        :worker_count => 25,
        :server => 'localhost:6379',
        :pidfile => nil,
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

        o.on '-c', '--concurrency INT', "Worker threads to use" do |arg|
          @options[:worker_count] = arg.to_i
        end
      end

      @parser.banner = "sidekiq -q foo,1 -q bar,2 <more options>"
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
