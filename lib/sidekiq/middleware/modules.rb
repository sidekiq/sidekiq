module Sidekiq
  module ServerMiddleware
    attr_accessor :config
    def redis_pool
      config.redis_pool
    end

    def logger
      config.logger
    end

    def redis(&block)
      config.redis(&block)
    end
  end

  # no difference for now
  ClientMiddleware = ServerMiddleware
end
