require "sidekiq/component"
require "sidekiq/fetch"

module Sidekiq
  # A Sidekiq::Capsule is the set of resources necessary to
  # process one or more queues with a given concurrency.
  class Capsule
    include Sidekiq::Component

    attr_reader :name
    attr_reader :queues
    attr_reader :strict
    attr_accessor :concurrency
    attr_accessor :fetch_class

    def initialize(name, config)
      @name = name
      @config = config
      @queues = ["default"]
      @concurrency = 10
      @strict = true
      @fetch_class = Sidekiq::BasicFetch
    end

    def fetcher
      @fetcher ||= fetch_class.new(self)
    end

    def stop
      @fetcher&.bulk_requeue([], nil)
    end

    def queues=(val)
      @queues = Array(val).each_with_object([]) do |qstr, memo|
        name, weight = qstr.split(",")
        @strict = false if weight.to_i > 0
        [weight.to_i, 1].max.times do
          memo << name
        end
      end
    end

    def client_middleware
      @client_chain ||= config.client_middleware.dup
      yield @client_chain if block_given?
      @client_chain
    end

    def server_middleware
      @server_chain ||= config.server_middleware.dup
      yield @server_chain if block_given?
      @server_chain
    end

    def redis_pool
      # connection pool is lazy, it will not create connections unless you actually need them
      # so don't be skimpy!
      @redis ||= config.new_redis_pool(@concurrency)
    end

    def redis
      raise ArgumentError, "requires a block" unless block_given?
      redis_pool.with do |conn|
        retryable = true
        begin
          yield conn
        rescue RedisClientAdapter::BaseError => ex
          # 2550 Failover can cause the server to become a replica, need
          # to disconnect and reopen the socket to get back to the primary.
          # 4495 Use the same logic if we have a "Not enough replicas" error from the primary
          # 4985 Use the same logic when a blocking command is force-unblocked
          # The same retry logic is also used in client.rb
          if retryable && ex.message =~ /READONLY|NOREPLICAS|UNBLOCKED/
            conn.close
            retryable = false
            retry
          end
          raise
        end
      end
    end

    def logger
      config.logger
    end

    # Passthru any other calls to the underlying config
    def method_missing(name, *args, **kwargs)
      config.send(name, *args, **kwargs)
    end

    def respond_to_missing?(name)
      true
    end
  end
end
