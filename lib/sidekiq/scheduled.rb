require 'sidekiq'
require 'sidekiq/util'
require 'sidekiq/actor'

module Sidekiq
  module Scheduled

    POLL_INTERVAL = 15

    ##
    # The Poller checks Redis every N seconds for messages in the retry or scheduled
    # set have passed their timestamp and should be enqueued.  If so, it
    # just pops the message back onto its original queue so the
    # workers can pick it up like any other message.
    class Poller
      include Util
      include Actor

      SETS = %w(retry schedule)

      def poll(first_time=false)
        watchdog('scheduling poller thread died!') do
          add_jitter if first_time

          begin
            # A message's "score" in Redis is the time at which it should be processed.
            # Just check Redis for the set of messages with a timestamp before now.
            now = Time.now.to_f
            Sidekiq.redis do |conn|
              SETS.each do |sorted_set|
                next unless any_eligible_messages?(conn, sorted_set, now)

                # Get the next item in the queue if it's score (time to execute) is <= now.
                # We need to go through the list one at a time to reduce the risk of something
                # going wrong between the time jobs are popped from the scheduled queue and when
                # they are pushed onto a work queue and losing the jobs.
                while message = get_next_message(conn, sorted_set, now)
                  Sidekiq::Client.push(message)
                  logger.debug { "enqueued #{sorted_set}: #{message}" }
                end
              end
            end
          rescue => ex
            # Most likely a problem with redis networking.
            # Punt and try again at the next interval
            logger.error ex.message
            logger.error ex.backtrace.first
          end

          after(poll_interval) { poll }
        end
      end

      # Retrieve and delete the first eligible message in the set. If there
      # are no such messages, return nil.
      def get_next_message(conn, sorted_set, end_time)
        message, score = grab_first_message_with_score(conn, sorted_set)

        if message
          if score <= end_time
            Sidekiq.load_json(message)
          else
            conn.zadd(sorted_set, score.to_s, message)
            nil
          end
        end
      rescue => e
        # If something goes wrong after we grab the message, try to put it back
        # before re-raising.
        if message
          conn.zadd(sorted_set, score.to_s, message)
        end
        raise
      end

      private

      # Are there any messages in this set that are ready to be enqueued?
      def any_eligible_messages?(conn, sorted_set, end_time)
        conn.zcount(sorted_set, '-inf', end_time.to_s) > 0
      end

      # Atomically retrieve and delete the first message in the set, regardless
      # of eligibility.
      def grab_first_message_with_score(conn, sorted_set)
        messages = nil
        conn.multi do
          messages = conn.zrange(sorted_set, 0, 0, :withscores => true)
          conn.zremrangebyrank(sorted_set, 0, 0)
        end
        messages.value.first
      end

      def poll_interval
        Sidekiq.options[:poll_interval] || POLL_INTERVAL
      end

      def add_jitter
        begin
          sleep(poll_interval * rand)
        rescue Celluloid::Task::TerminatedError
          # Hit Ctrl-C when Sidekiq is finished booting and we have a chance
          # to get here.
        end
      end
    end
  end
end
