# frozen_string_literal: true

require "connection_pool"
require "redis-client"
require "uri"

module Sidekiq
  class RedisClientConnection < RedisConnection
    class CompatClient
      module Commands
        def info
          @client.call("INFO").lines(chomp: true).map { |l| l.split(":", 2) }.select { |l| l.size == 2 }.to_h
        end

        def evalsha(sha, keys: [], argv: [])
          @client.call("EVALSHA", sha, keys.size, *keys, *argv)
        end

        def brpop(*args)
          @client.blocking_call(false, "BRPOP", *args)
        end

        def call(*args)
          @client.call(*args)
        end

        private

        def simple_call(*args)
          @client.call(__callee__, *args)
        end

        def with_scores_call(*args, with_scores: false)
          args.unshift(__callee__)
          args << "WITHSCORES" if with_scores
          @client.call(*args)
        end

        %i[
          exists expire flushdb get hget hgetall hmget hmset hset incr incrby llen lpop lpush lrange
          lrem mget mset ping pttl rpush rpop sadd scard smembers script set srem
          type unlink zadd zcard zincrby zrem zremrangebyrank zremrangebyscore
        ].each do |command|
          alias_method command, :simple_call
          public command
        end

        %i[zrange zrangebyscore zrevrange].each do |command|
          alias_method command, :with_scores_call
          public command
        end
      end

      class Pipeline
        include Commands

        def initialize(client)
          @client = client
        end
      end

      include Commands

      def initialize(client)
        @client = client
      end

      def id
        @client.id
      end

      def read_timeout
        @client.read_timeout
      end

      def exists?(key)
        @client.call("EXISTS", key) > 0
      end

      def pipelined
        @client.pipelined { |p| yield Pipeline.new(p) }
      end

      def multi
        @client.multi { |p| yield Pipeline.new(p) }
      end

      def sscan_each(*args, &block)
        @client.sscan(*args, &block)
      end
      ruby2_keywords :sscan_each if respond_to?(:ruby2_keywords, true)

      def zscan_each(*args, &block)
        @client.zscan(*args, &block)
      end
      ruby2_keywords :zscan_each if respond_to?(:ruby2_keywords, true)

      def disconnect!
        @client.close
      end

      def config
        @client.config
      end

      def connection
        {id: @client.id}
      end

      def redis
        self
      end
    end

    BaseError = RedisClient::Error
    CommandError = RedisClient::CommandError

    class << self
      private

      def build_pool(size, pool_timeout, symbolized_options)
        redis_config = build_config(symbolized_options)
        ConnectionPool.new(timeout: pool_timeout, size: size) do
          CompatClient.new(redis_config.new_client)
        end
      end

      def build_config(options)
        opts = client_opts(options)
        if opts.key?(:sentinels)
          RedisClient.sentinel(**opts)
        else
          RedisClient.config(**opts)
        end
      end

      def client_opts(options)
        opts = options.dup

        opts.delete(:size)
        opts.delete(:pool_timeout)

        if opts[:network_timeout]
          opts[:timeout] = opts[:network_timeout]
          opts.delete(:network_timeout)
        end

        opts[:name] = opts.delete(:master_name) if opts.key?(:master_name)
        opts[:role] = opts[:role].to_sym if opts.key?(:role)
        opts.delete(:url) if opts.key?(:sentinels)

        # Issue #3303, redis-rb will silently retry an operation.
        # This can lead to duplicate jobs if Sidekiq::Client's LPUSH
        # is performed twice but I believe this is much, much rarer
        # than the reconnect silently fixing a problem; we keep it
        # on by default.
        opts[:reconnect_attempts] ||= 1

        opts
      end
    end
  end
end
