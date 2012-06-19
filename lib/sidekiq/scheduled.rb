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

          # A message's "score" in Redis is the time at which it should be processed.
          # Just check Redis for the set of messages with a timestamp before now.
          now = Time.now.to_f.to_s
          Sidekiq.redis do |conn|
            SETS.each do |sorted_set|
              if sorted_set == 'schedule'
                messages = scheduled_messages
              else
                (messages, _) = conn.multi do
                  conn.zrangebyscore(sorted_set, '-inf', now)
                  conn.zremrangebyscore(sorted_set, '-inf', now)
                end
              end

              messages.each do |message|
                logger.debug { "enqueued #{sorted_set}: #{message}" }
                msg = Sidekiq.load_json(message)
                conn.rpush("queue:#{msg['queue']}", message)
              end
            end
          end

          after(POLL_INTERVAL) { poll }
        end
      end

      private

      def add_jitter
        begin
          sleep(POLL_INTERVAL * rand)
        rescue Celluloid::Task::TerminatedError
          # Hit Ctrl-C when Sidekiq is finished booting and we have a chance
          # to get here.
        end
      end

      def scheduled_messages
        [].tap do |messages|
          while timestamp = find_next_timestamp
            while message = Sidekiq.redis { |conn| conn.lpop("schedule:#{timestamp}") }
              messages << message
            end
            Sidekiq::Client.remove_scheduled_queue(timestamp)
          end
        end
      end

      def find_next_timestamp
        timestamp = Sidekiq.redis { |conn| conn.zrangebyscore('schedule', '-inf', Time.now.to_f, :limit => [0, 1]) }
        if timestamp.is_a?(Array)
          timestamp = timestamp.first
        end
      end

    end
  end
end
