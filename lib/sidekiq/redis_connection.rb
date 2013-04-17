require 'connection_pool'
require 'redis'

module Sidekiq
  class RedisConnection
    class << self

      def create(options={})
        url = options[:url] || determine_redis_provider || 'redis://localhost:6379/0'
        # need a connection for Fetcher and Retry
        size = options[:size] || (Sidekiq.server? ? (Sidekiq.options[:concurrency] + 2) : 5)

        log_info(url, options)

        ConnectionPool.new(:timeout => 1, :size => size) do
          build_client(url, options[:namespace], options[:driver] || 'ruby')
        end
      end

      private

      def build_client(url, namespace, driver)
        client = Redis.connect(:url => url, :driver => driver)
        if namespace
          require 'redis/namespace'
          Redis::Namespace.new(namespace, :redis => client)
        else
          client
        end
      end

      def log_info(url, options)
        opts = options.dup
        opts.delete(:url)
        if Sidekiq.server?
          Sidekiq.logger.info("Booting #{Sidekiq::NAME} #{Sidekiq::VERSION} using #{url} with options #{opts}")
        else
          Sidekiq.logger.info("#{Sidekiq::NAME} client using #{url} with options #{opts}")
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
