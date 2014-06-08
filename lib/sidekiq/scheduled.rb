require 'sidekiq'
require 'sidekiq/util'
require 'sidekiq/actor'

module Sidekiq
  module Scheduled

    INITIAL_WAIT = 10

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
          initial_wait if first_time

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

                  # Pop item off the queue and add it to the work queue. If the job can't be popped from
                  # the queue, it's because another process already popped it so we can move on to the
                  # next one.
                  if conn.zrem(sorted_set, message)
                    Sidekiq::Client.push(Sidekiq.load_json(message))
                    logger.debug { "enqueued #{sorted_set}: #{message}" }
                  end
                end
              end
            end
          rescue => ex
            # Most likely a problem with redis networking.
            # Punt and try again at the next interval
            logger.error ex.message
            logger.error ex.backtrace.first
          end

          after(poll_interval * rand) { poll }
        end
      end

      private

      # We do our best to tune poll_interval to the size of the active Sidekiq
      # cluster.  If you have 30 processes and poll every 15 seconds, that means one
      # Sidekiq is checking Redis every 0.5 seconds - way too often for most people
      # and really bad if the retry or scheduled sets are large.
      #
      # Instead try to avoid polling more than once every 15 seconds.  If you have
      # 30 Sidekiq processes, we'll set poll_interval to 30 * 15 * 2 or 900 seconds.
      # To keep things statistically random, we'll sleep a random amount between
      # 0 and 900 seconds for each poll or 450 seconds on average.  Otherwise restarting
      # all your Sidekiq processes at the same time will lead to them all polling at
      # the same time: the thundering herd problem.
      #
      # We only do this if poll_interval is unset (the default).
      def poll_interval
        Sidekiq.options[:poll_interval] ||= begin
          pcount = Sidekiq.redis {|c| c.scard('processes') } || 1
          pcount * 15 * 2
        end
      end

      def initial_wait
        begin
          # Have all processes sleep between 10-15 seconds.  10 seconds
          # to give time for the heartbeat to register and 5 random seconds
          # to ensure they don't all hit Redis at the same time.
          sleep(INITIAL_WAIT)
          sleep(5 * rand)
        rescue Celluloid::Task::TerminatedError
          # Hit Ctrl-C when Sidekiq is finished booting and we have a chance
          # to get here.
        end
      end

    end
  end
end
