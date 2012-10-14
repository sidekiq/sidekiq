require 'connection_pool'
require 'redis'
require 'redis/namespace'

module Sidekiq
  class RedisConnection
    def self.create(options={})
      url = options[:url] || determine_redis_provider || 'redis://localhost:6379/0'
      driver = options[:driver] || 'ruby'
      # need a connection for Fetcher and Retry
      size = options[:size] || (Sidekiq.server? ? (Sidekiq.options[:concurrency] + 2) : 5)

      ConnectionPool.new(:timeout => 1, :size => size) do
        build_client(url, options[:namespace], driver)
      end
    end

    def self.build_client(url, namespace, driver)
      client = Redis.connect(:url => url, :driver => driver)
      if namespace
        Redis::Namespace.new(namespace, :redis => client)
      else
        client
      end
    end
    private_class_method :build_client

    def self.determine_redis_provider
      provider = if ENV.has_key? 'REDISTOGO_URL'
        'REDISTOGO_URL'
      else
        ENV['REDIS_PROVIDER'] || 'REDIS_URL'
      end
      ENV[provider]
    end
    private_class_method :determine_redis_provider
  end
end
