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
    attr_accessor :queues
    attr_reader :default_worker_options
    attr_reader :pool

    # an arbitrary set of entries
    attr_reader :labels
    attr_accessor :tag

    def initialize
      @queues = ["default"]
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
      @labels = Set.new
      @tag = ""
      @components = []
    end

    # components will be called back when the configuration is
    # finalized so they can pull config'd items like logger, pool, etc.
    def register_component(comp)
      @components << comp
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

    def finalize
      @pool ||= ConnectionPool.new(size: concurrency + 2, timeout: 5) { Redis.new(redis) }

      @components.each do |comp|
        comp.finalize(self)
      end
      @components = nil
    end

  end
end
