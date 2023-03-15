# frozen_string_literal: true

#
# Simple middleware to log source locations from where the job was enqueued.
# Use it by requiring it in your initializer:
#
#     require 'sidekiq/middleware/enqueue_source_logger'
#
module Sidekiq
  module Middleware
    class EnqueueSourceLogger
      include Sidekiq::ClientMiddleware

      def call(jobclass, _job, _queue, _pool)
        source = extract_enqueue_source_location(caller)
        logger.info(<<~EOM)
          #{jobclass} enqueued
            ↳ #{source}
        EOM

        yield
      end

      private

      def extract_enqueue_source_location(locations)
        backtrace_cleaner = Sidekiq.default_configuration[:backtrace_cleaner]
        backtrace_cleaner.call(locations.lazy).first
      end
    end
  end
end

Sidekiq.configure_client do |config|
  config.client_middleware do |chain|
    chain.add Sidekiq::Middleware::EnqueueSourceLogger
  end
end

Sidekiq.configure_server do |config|
  config.client_middleware do |chain|
    chain.add Sidekiq::Middleware::EnqueueSourceLogger
  end
end
