require "logger"
module Sidekiq
  class Configuration
    attr_accessor :concurrency
    attr_accessor :environment
    attr_accessor :shutdown_timeout
    attr_reader :server_middleware
    attr_reader :event_hooks
    attr_reader :error_handlers
    attr_reader :death_handlers

    attr_accessor :logger
    attr_accessor :log_level
    attr_accessor :redis
    attr_reader :default_worker_options
    attr_reader :pool

    def initialize
      @concurrency = 10
      @shutdown_timeout = 25
      @logger = ::Logger.new($stdout)
      @logger.level = ::Logger::INFO
      @environment = "development"
      @default_worker_options = {"retry": 25, "queue": "default"}
      @redis = {url: ENV[(ENV["REDIS_PROVIDER"] || "REDIS_URL")] || "redis://localhost:6379/0"}
      @client_middleware = Sidekiq::Middleware::Chain.new
      @server_middleware = Sidekiq::Middleware::Chain.new
      @event_hooks = {
        startup: [],
        quiet: [],
        shutdown: [],
        heartbeat: []
      }
      @death_handlers = []
      @error_handlers = [->(ex, ctx) {
        @logger.warn(Sidekiq.dump_json(ctx)) unless ctx.empty?
        @logger.warn("#{ex.class.name}: #{ex.message}")
        @logger.warn(ex.backtrace.join("\n")) unless ex.backtrace.nil?
      }]
    end

    def on(event, &block)
      raise ArgumentError, "Symbols only please: #{event}" unless event.is_a?(Symbol)
      raise ArgumentError, "Invalid event name: #{event}" unless event_hooks.key?(event)
      @event_hooks[event] << block
    end

    def client_middleware
      if block_given?
        yield @client_middleware
      else
        @client_middleware
      end
    end

    def freeze!
      @pool = ConnectionPool.new(size: @concurrency + 2, timeout: 5) { Redis.new(@redis) }
    end

    private

    def boot
      # @runner = Sidekiq::Runner.new(self)

      # fire_event(:startup)
    end

    def fire_event(event, options = {})
      reverse = options[:reverse]
      reraise = options[:reraise]

      arr = @event_hooks[event]
      arr.reverse! if reverse
      arr.each do |block|
        if block.arity == 0
          block.call
        else
          block.call(@runner)
        end
      rescue => ex
        handle_exception(ex, {context: "Exception during Sidekiq lifecycle event.", event: event})
        raise ex if reraise
      end
      arr.clear
    end

    def handle_exception(ex, ctx = {})
      error_handlers.each do |handler|
        handler.call(ex, ctx)
      rescue => ex
        logger.error "!!! ERROR HANDLER THREW AN ERROR !!!"
        logger.error ex
        logger.error ex.backtrace.join("\n") unless ex.backtrace.nil?
      end
    end
  end
end
