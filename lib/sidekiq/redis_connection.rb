require 'connection_pool'
require 'redis/namespace'

module Sidekiq
  class RedisConnection
    def self.create(url = nil, namespace = nil, pool = true)
      @namespace = namespace ? namespace : nil
      @url = url ? url : nil

      if pool
        ConnectionPool.new { connect }
      else
        connect
      end
    end

    def self.connect
      r = Redis.connect(:url => url)
      if namespace
        Redis::Namespace.new(namespace, :redis => r)
      else
        r
      end
    end

    def self.namespace
      @namespace
    end

    def self.url
      @url || ENV['REDISTOGO_URL'] || 'redis://localhost:6379/0'
    end

    def self.namespace=(namespace)
      @namespace = namespace
    end
  end
end
