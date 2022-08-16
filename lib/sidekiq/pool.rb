module Sidekiq
  module PoolAccess
    def redis_pool
      Thread.current[:sidekiq_redis_pool] || (@redis ||= Sidekiq::RedisConnection.create)
    end
  end
end
