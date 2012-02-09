require 'connection_pool'
require 'redis/namespace'

module Sidekiq
  class RedisConnection
    def self.create(url = nil, namespace = nil, pool = true)
      @namespace = namespace if namespace
      @url = url if url
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
      @namespace ||= nil
    end

    def self.url
      ENV['REDISTOGO_URL'] || (@url = nil)
    end

    def self.namespace=(namespace)
      @namespace = namespace
    end
  end
end
