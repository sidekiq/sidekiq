require 'sidekiq/scheduled'

module Sidekiq
  module Middleware
    module Server
      ##
      # Automatically retry jobs that fail in Sidekiq.
      # Sidekiq's retry support assumes a typical development lifecycle:
      # 0. push some code changes with a bug in it
      # 1. bug causes message processing to fail, sidekiq's middleware captures
      #    the message and pushes it onto a retry queue
      # 2. sidekiq retries messages in the retry queue multiple times with
      #    an exponential delay, the message continues to fail
      # 3. after a few days, a developer deploys a fix.  the message is
      #    reprocessed successfully.
      # 4. if 3 never happens, sidekiq will eventually give up and throw the
      #    message away. If the worker defines a method called 'retries_exhausted',
      #    this will be called before throwing the message away. If the
      #    'retries_exhausted' method throws an exception, it's dropped and logged.
      #
      # A message looks like:
      #
      #     { 'class' => 'HardWorker', 'args' => [1, 2, 'foo'] }
      #
      # The 'retry' option also accepts a number (in place of 'true'):
      #
      #     { 'class' => 'HardWorker', 'args' => [1, 2, 'foo'], 'retry' => 5 }
      #
      # The job will be retried this number of times before giving up. (If simply
      # 'true', Sidekiq retries 25 times)
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

        DEFAULT_MAX_RETRY_ATTEMPTS = 25

        def call(worker, msg, queue)
          yield
        rescue Sidekiq::Shutdown
          # ignore, will be pushed back onto queue during hard_shutdown
          raise
        rescue Exception => e
          raise e unless msg['retry']
          max_retry_attempts = retry_attempts_from(msg['retry'], DEFAULT_MAX_RETRY_ATTEMPTS)

          msg['queue'] = if msg['retry_queue']
            msg['retry_queue']
          else
            queue
          end
          msg['error_message'] = e.message
          msg['error_class'] = e.class.name
          count = if msg['retry_count']
            msg['retried_at'] = Time.now.utc
            msg['retry_count'] += 1
          else
            msg['failed_at'] = Time.now.utc
            msg['retry_count'] = 0
          end

          if msg['backtrace'] == true
            msg['error_backtrace'] = e.backtrace
          elsif msg['backtrace'] == false
            # do nothing
          elsif msg['backtrace'].to_i != 0
            msg['error_backtrace'] = e.backtrace[0..msg['backtrace'].to_i]
          end

          if count < max_retry_attempts
            delay = delay_for(worker, count)
            logger.debug { "Failure! Retry #{count} in #{delay} seconds" }
            retry_at = Time.now.to_f + delay
            payload = Sidekiq.dump_json(msg)
            Sidekiq.redis do |conn|
              conn.zadd('retry', retry_at.to_s, payload)
            end
          else
            # Goodbye dear message, you (re)tried your best I'm sure.
            retries_exhausted(worker, msg)
          end

          raise e
        end

        def retries_exhausted(worker, msg)
          logger.debug { "Dropping message after hitting the retry maximum: #{msg}" }
          if worker.respond_to?(:retries_exhausted)
            logger.warn { "Defining #{worker.class.name}#retries_exhausted as a method is deprecated, use `sidekiq_retries_exhausted` callback instead http://git.io/Ijju8g" }
            worker.retries_exhausted(*msg['args'])
          elsif worker.sidekiq_retries_exhausted_block?
            worker.sidekiq_retries_exhausted_block.call(msg)
          end

        rescue Exception => e
          handle_exception(e, "Error calling retries_exhausted")
        end

        def retry_attempts_from(msg_retry, default)
          if msg_retry.is_a?(Fixnum)
            msg_retry
          else
            default
          end
        end

        def delay_for(worker, count)
          worker.sidekiq_retry_in_block? && retry_in(worker, count) || seconds_to_delay(count)
        end

        # delayed_job uses the same basic formula
        def seconds_to_delay(count)
          (count ** 4) + 15 + (rand(30)*(count+1))
        end

        def retry_in(worker, count)
          begin
            worker.sidekiq_retry_in_block.call(count)
          rescue Exception => e
            logger.error { "Failure scheduling retry using the defined `sidekiq_retry_in` in #{worker.class.name}, falling back to default: #{e.message}"}
            nil
          end
        end

      end
    end
  end
end
