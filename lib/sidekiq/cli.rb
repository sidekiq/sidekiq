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
      parse_options(args)
      validate!
      boot_system
    end

    def run
      Sidekiq::Manager.redis = RedisConnection.create(:url => @options[:server], :namespace => @options[:namespace])
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

      raise ArgumentError, "#{@options[:require]} does not exist" if !File.exist?(@options[:require])

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
      @options = {
        :queues => [],
        :processor_count => 25,
        :require => '.',
        :environment => nil,
      }

      @parser = OptionParser.new do |o|
        o.on "-q", "--queue QUEUE,WEIGHT", "Queue to process, with optional weight" do |arg|
          (q, weight) = arg.split(",")
          (weight || 1).to_i.times do
            @options[:queues] << q
          end
        end

        o.on "-v", "--verbose", "Print more verbose output" do
          Sidekiq::Util.logger.level = Logger::DEBUG
        end

        o.on "-n", "--namespace NAMESPACE", "namespace worker queues are under" do |arg|
          @options[:namespace] = arg
        end

        o.on "-s", "--server LOCATION", "Where to find Redis" do |arg|
          @options[:server] = arg
        end

        o.on '-e', '--environment ENV', "Application environment" do |arg|
          @options[:environment] = arg
        end

        o.on '-r', '--require [PATH|DIR]', "Location of Rails application with workers or file to require" do |arg|
          @options[:require] = arg
        end

        o.on '-c', '--concurrency INT', "processor threads to use" do |arg|
          @options[:processor_count] = arg.to_i
        end
      end

      @parser.banner = "sidekiq [options]"
      @parser.on_tail "-h", "--help", "Show help" do
        logger.info @parser
        die 1
      end
      @parser.parse!(argv)
    end

  end
end
