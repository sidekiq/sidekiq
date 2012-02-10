require 'connection_pool'
require 'redis/namespace'

module Sidekiq
  class RedisConnection
<<<<<<< HEAD
    def self.create(options={})
      url = options[:url] || ENV['REDISTOGO_URL'] || 'redis://localhost:6379/0'
      client = build_client(url, options[:namespace])
      return ConnectionPool.new { client } if options[:use_pool]
      client
=======
    def self.create(url=nil, namespace=nil, pool=true)
      @namespace = namespace
      @url = url

      if pool
        ConnectionPool.new { connect }
      else
        connect
      end
>>>>>>> c2877d690fac59ee18006912aeecd3babb072dc1
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
