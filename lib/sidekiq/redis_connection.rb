require 'connection_pool'
require 'redis'

module Sidekiq
  class RedisConnection
    class << self

      def create(options={})
        url = options[:url] || determine_redis_provider
        if url
          options[:url] = url
        end
        
        # need a connection for Fetcher and Retry
        size = options[:size] || (Sidekiq.server? ? (Sidekiq.options[:concurrency] + 2) : 5)
        pool_timeout = options[:pool_timeout] || 1

        log_info(options)

        ConnectionPool.new(:timeout => pool_timeout, :size => size) do
          build_client(options)
        end
      end

      private

      def build_client(options)
        namespace = options[:namespace]

        client = Redis.new client_opts(options)
        if namespace
          require 'redis/namespace'
          Redis::Namespace.new(namespace, :redis => client)
        else
          client
        end
      end

      def client_opts(options)
        opts = options.dup
        if opts[:namespace]
          opts.delete(:namespace)
        end

        if opts[:network_timeout]
          opts[:timeout] = opts[:network_timeout]
          opts.delete(:network_timeout)
        end

        opts[:driver] = opts[:driver] || 'ruby'

        opts
      end

      def log_info(options)
        if Sidekiq.server?
          Sidekiq.logger.info("Booting Sidekiq #{Sidekiq::VERSION} with redis options #{options}")
        else
          Sidekiq.logger.info("#{Sidekiq::NAME} client with redis options #{options}")
        end
      end

      def determine_redis_provider
        # REDISTOGO_URL is only support for legacy reasons
        return ENV['REDISTOGO_URL'] if ENV['REDISTOGO_URL']
        provider = ENV['REDIS_PROVIDER'] || 'REDIS_URL'
        ENV[provider]
      end

    end
  end
end
