# frozen_string_literal: true

require "connection_pool"
require "redis-client"
require "uri"

module Sidekiq
  module RedisConnection
    class RedisClientAdapter
      BaseError = RedisClient::Error
      CommandError = RedisClient::CommandError

      class CompatClient
        module Commands
          def info
            @client.call("INFO").lines(chomp: true).map { |l| l.split(":", 2) }.select { |l| l.size == 2 }.to_h
          end

          def evalsha(sha, keys, argv)
            @client.call("EVALSHA", sha, keys.size, *keys, *argv)
          end

          def brpoplpush(*args)
            @client.blocking_call(false, "BRPOPLPUSH", *args)
          end

          def brpop(*args)
            @client.blocking_call(false, "BRPOP", *args)
          end

          def call(*args)
            @client.call(*args)
          end

          def sismember(*args)
            @client.call("SISMEMBER", *args) == 1
          end

          def publish(channel, msg)
            @client.call("PUBLISH", channel, msg)
          end

          def set(key, value, ex: nil, nx: false, px: nil)
            command = ["SET", key, value]
            command << "NX" if nx
            command << "EX" if ex
            command << ex if ex
            command << "PX" if px
            command << px if px
            @client.call(*command) == "OK"
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
            del exists expire flushdb get hdel hget hgetall hlen hmget hmset hset hsetnx hincrby incr incrby llen lpop lpush lrange
            lrem mget mset ping pttl rpush rpop sadd scard smembers scan script srem ttl
            type unlink zadd zcard zincrby zrem zremrangebyrank zremrangebyscore rpoplpush
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

        def scan_each(*args, &block)
          @client.scan(*args, &block)
        end
        ruby2_keywords :scan_each if respond_to?(:ruby2_keywords, true)

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

        def _client
          @client
        end
      end

      def initialize(options)
        opts = client_opts(options)
        @config = if opts.key?(:sentinels)
          RedisClient.sentinel(**opts)
        else
          RedisClient.config(**opts)
        end
      end

      def new_client
        CompatClient.new(@config.new_client)
      end

      private

      def client_opts(options)
        opts = options.dup

        if opts[:namespace]
          Sidekiq.logger.error("Your Redis configuration uses the namespace '#{opts[:namespace]}' but this feature isn't supported by redis-client. " \
           "Either use the redis adapter or remove the namespace.")
          Kernel.exit(-127)
        end

        opts.delete(:size)
        opts.delete(:pool_timeout)

        if opts[:network_timeout]
          opts[:timeout] = opts[:network_timeout]
          opts.delete(:network_timeout)
        end

        if opts[:driver]
          opts[:driver] = opts[:driver].to_sym
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
