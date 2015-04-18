#
# Middleware to clean retry job exceptions when they are requeued.
module Sidekiq
  module Middleware
    module Client
      class RetryJobCleaner
        def call(worker_class, msg, queue, redis_pool)
          msg.delete('error_message')
          msg.delete('error_class')
          msg.delete('error_backtrace')

          yield
        end
      end
    end
  end
end

