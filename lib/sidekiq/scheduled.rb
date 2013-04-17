require 'sidekiq'
require 'sidekiq/util'
require 'celluloid'

module Sidekiq
  module Scheduled

    POLL_INTERVAL = 15

    ##
    # The Poller checks Redis every N seconds for messages in the retry or scheduled
    # set have passed their timestamp and should be enqueued.  If so, it
    # just pops the message back onto its original queue so the
    # workers can pick it up like any other message.
    class Poller
      include Celluloid
      include Sidekiq::Util

      SETS = %w(retry schedule)

      def poll(first_time=false)
        watchdog('scheduling poller thread died!') do
          add_jitter if first_time

          begin
            # A message's "score" in Redis is the time at which it should be processed.
            # Just check Redis for the set of messages with a timestamp before now.
            now = Time.now.to_f.to_s
            Sidekiq.redis do |conn|
              SETS.each do |sorted_set|
                # Get the next item in the queue if it's score (time to execute) is <= now.
                # We need to go through the list one at a time to reduce the risk of something
                # going wrong between the time jobs are popped from the scheduled queue and when
                # they are pushed onto a work queue and losing the jobs.
                while message = conn.zrangebyscore(sorted_set, '-inf', now, :limit => [0, 1]).first do
                  msg = Sidekiq.load_json(message)
                  # Pop item off the queue and add it to the work queue. If the job can't be popped from
                  # the queue, it's because another process already popped it so we can move on to the
                  # next one.
                  if conn.zrem(sorted_set, message)
                    conn.multi do
                      conn.sadd('queues', msg['queue'])
                      conn.lpush("queue:#{msg['queue']}", message)
                    end
                    logger.debug("enqueued #{sorted_set}: #{message}") if logger.debug?
                  end
                end
              end
            end
          rescue => ex
            # Most likely a problem with redis networking.
            # Punt and try again at the next interval
            logger.error ex.message
            logger.error(ex.backtrace.first)
          end

          after(poll_interval) { poll }
        end
      end

      private

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
