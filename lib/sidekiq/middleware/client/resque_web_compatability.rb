module Sidekiq
  module Middleware
    module Client
      class ResqueWebCompatability
        def initialize(redis)
          @redis = redis
        end

        #Add job queue to list of queues resque web displays
        def call(item, queue)
          @redis.sadd('queues', queue)

          yield
        end
      end
    end
  end
end
