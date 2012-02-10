require 'connection_pool'
require 'redis/namespace'

module Sidekiq
  class RedisConnection
    def self.create(url=nil, namespace=nil, pool=true)
      @namespace = namespace
      @url = url

      if pool
        ConnectionPool.new { connect }
      else
        connect
      end
    end

    def self.connect
      if namespace
        Redis::Namespace.new(namespace, :redis => redis_connection)
      else
        redis_connection
      end
    end

    def self.namespace
      @namespace
    end

    def self.url
      @url || ENV['REDISTOGO_URL'] || 'redis://localhost:6379/0'
    end

    private
    
    def self.redis_connection
      Redis.connect(:url => url)
    end
  end
end
