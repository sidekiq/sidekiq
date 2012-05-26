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

      def poll
        watchdog('scheduling poller thread died!') do
          # A message's "score" in Redis is the time at which it should be processed.
          # Just check Redis for the set of messages with a timestamp before now.
          now = Time.now.to_f.to_s
          Sidekiq.redis do |conn|
            SETS.each do |sorted_set|
              (messages, _) = conn.multi do
                conn.zrangebyscore(sorted_set, '-inf', now)
                conn.zremrangebyscore(sorted_set, '-inf', now)
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

    end
  end
end
