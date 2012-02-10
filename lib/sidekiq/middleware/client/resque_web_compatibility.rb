module Sidekiq
  module Middleware
    module Client
      class ResqueWebCompatibility
        def initialize(redis)
          @redis = redis
        end

        def call(item, queue)
          @redis.sadd('queues', queue)
          yield
        end

      end
    end
  end
end
