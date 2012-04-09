require 'connection_pool'
require 'redis'
require 'redis/namespace'

module Sidekiq
  class RedisConnection
    def self.create(options={})
      url = options[:url] || ENV['REDISTOGO_URL'] || 'redis://localhost:6379/0'
      # need a connection for Fetcher and Retry
      size = options[:size] || (Sidekiq.server? ? (Sidekiq.options[:concurrency] + 2) : 5)

      ConnectionPool.new(:timeout => 1, :size => size) do
        build_client(url, options[:namespace])
      end
    end

    def self.build_client(url, namespace)
      client = Redis.connect(:url => url)
      if namespace
        Redis::Namespace.new(namespace, :redis => client)
      else
        client
      end
    end
    private_class_method :build_client
  end
end
