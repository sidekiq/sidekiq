module Sidekiq
  module Middleware
    module Client
      class ResqueWebCompatibility

        def call(item, queue)
          Sidekiq.redis.sadd('queues', queue)
          yield
        end

      end
    end
  end
end
