require 'optparse'
require 'sidekiq'

module Sidekiq
  class CLI
    def initialize
      parse_options
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

    def log(str)
      STDOUT.puts str
    end

    def error(str)
      @STDERR.puts "ERROR: #{str}"
    end

    def parse_options(argv=ARGV)
      @options = {
        :quiet => false,
        :queues => [],
        :worker_threads => 25,
        :server => 'localhost:6379'
      }

      @parser = OptionParser.new do |o|
        o.on "-q", "--queue QUEUE", "Queue to process" do |arg|
          @options[:queues].concat arg.split(",")
        end

        o.on "-C", "--config PATH", "Load PATH as a config file" do |arg|
          @options[:config_file] = arg
        end

        o.on "--pidfile PATH", "Use PATH as a pidfile" do |arg|
          @options[:pidfile] = arg
        end

        o.on "-q", "--quiet", "Quiet down the output" do
          @options[:quiet] = true
        end

        o.on "-s", "--server LOCATION", "Where to find the server" do |arg|
          @options[:server] = arg
        end

        o.on '-t', '--threads INT', "worker threads to use" do |arg|
          @options[:worker_threads] = arg.to_i
        end
      end

      @parser.banner = "sidekiq <options>"
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
