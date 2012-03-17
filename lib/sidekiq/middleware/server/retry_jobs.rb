require 'sidekiq/retry'

module Sidekiq
  module Middleware
    module Server
      ##
      # Automatically retry jobs that fail in Sidekiq.
      # A message looks like:
      #
      #     { 'class' => 'HardWorker', 'args' => [1, 2, 'foo'] }
      #
      # We'll add a bit more data to the message to support retries:
      #
      #  * 'queue' - the queue to use
      #  * 'retry_count' - number of times we've retried so far.
      #  * 'error_message' - the message from the exception
      #  * 'error_class' - the exception class
      #  * 'failed_at' - the first time it failed
      #  * 'retried_at' - the last time it was retried
      # 
      # We don't store the backtrace as that can add a lot of overhead
      # to the message and everyone is using Airbrake, right?
      class RetryJobs
        def call(worker, msg, queue)
          yield
        rescue => e
          msg['queue'] = queue
          msg['error_message'] = e.message
          msg['error_class'] = e.class.name
          count = if msg['retry_count']
            msg['retried_at'] = Time.now.utc
            msg['retry_count'] += 1
          else
            msg['failed_at'] = Time.now.utc
            msg['retry_count'] = 0
          end

          if count <= Sidekiq::Retry::MAX_COUNT
            retry_at = Time.now.to_f + Sidekiq::Retry::DELAY.call(count)
            payload = MultiJson.encode(msg)
            Sidekiq.redis do |conn| 
              conn.zadd('retry', retry_at, payload)
            end
          else
            # Pour a 40 out for our friend.  Goodbye dear message,
            # You (re)tried your best, I'm sure.
            Sidekiq::Util.logger.info("Dropping message after hitting the retry maximum: #{message}")
          end
          raise
        end
      end
    end
  end
end
