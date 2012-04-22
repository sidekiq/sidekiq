require 'multi_json'

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
        include Sidekiq::Util
        include Sidekiq::Retry

        def call(worker, msg, queue)
          yield
        rescue => e
          raise unless msg['retry']

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

          if count <= MAX_COUNT
            delay = DELAY.call(count)
            logger.debug { "Failure! Retry #{count} in #{delay} seconds" }
            retry_at = Time.now.to_f + delay
            payload = if MultiJson.respond_to?(:dump)
              MultiJson.dump(msg)
            else
              MultiJson.encode(msg)
            end
            Sidekiq.redis do |conn|
              conn.zadd('retry', retry_at.to_s, payload)
            end
          else
            # Goodbye dear message, you (re)tried your best I'm sure.
            logger.debug { "Dropping message after hitting the retry maximum: #{msg}" }
          end
          raise
        end

      end
    end
  end
end
