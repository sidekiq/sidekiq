require 'connection_pool'
require 'redis'

module Sidekiq
  class RedisConnection
    def self.create(options={})
      url = options[:url] || determine_redis_provider || 'redis://localhost:6379/0'
      # need a connection for Fetcher and Retry
      size = options[:size] || (Sidekiq.server? ? (Sidekiq.options[:concurrency] + 2) : 5)

      ConnectionPool.new(:timeout => 1, :size => size) do
        build_client(url, options[:namespace], options[:driver] || 'ruby')
      end
    end

    def self.build_client(url, namespace, driver)
      client = Redis.connect(:url => url, :driver => driver)
      if namespace
        require 'redis/namespace'
        Redis::Namespace.new(namespace, :redis => client)
      else
        client
      end
    end
    private_class_method :build_client

    # Not public
    def self.determine_redis_provider
      return ENV['REDISTOGO_URL'] if ENV['REDISTOGO_URL']
      provider = ENV['REDIS_PROVIDER'] || 'REDIS_URL'
      ENV[provider]
    end
  end
end
