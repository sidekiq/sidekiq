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
      # Optionally contains a 'retry_options' hash with these options:
      #
      #  * 'max_count' - max number of tries
      #  * 'falloff' - algorithm to use for falloff, 'linear' or 'exponential'
      #  * 'interval' - interval in between retries for linear falloff
      #  * 'expiration' - Do not retry after this date, can be nil
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
          retry_options = msg.fetch('retry_options', {})

          if can_be_retried?(msg, count, retry_options)
            delay = delay_time(msg, count, retry_options)
            logger.debug { "Failure! Retry #{count} in #{delay} seconds" }
            retry_at = Time.now.to_f + delay
            payload = MultiJson.encode(msg)
            Sidekiq.redis do |conn|
              conn.zadd('retry', retry_at.to_s, payload)
            end
          else
            # Goodbye dear message, you (re)tried your best I'm sure.
            logger.debug { "Dropping message after hitting the retry maximum: #{msg}" }
          end
          raise
        end

        def can_be_retried?(msg, count, retry_options)
          # Check expiration
          expiration = Time.parse(retry_options['expiration']) if retry_options['expiration']
          return false if expiration && Time.now.utc > expiration

          # Check retry count
          max_count = retry_options.fetch('max_count', MAX_COUNT)
          count <= max_count
        end

        def delay_time(msg, count, retry_options)
          return retry_options['interval'].to_f if retry_options['falloff'] == 'linear' && retry_options['interval']
          DELAY.call(count)
        end

      end
    end
  end
end
