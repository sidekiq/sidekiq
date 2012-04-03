require 'sidekiq'
require 'celluloid'

module Sidekiq
  ##
  # The Fetcher blocks on Redis, waiting for a message to process
  # from the queues.  It gets the message and hands it to the Manager
  # to assign to a ready Processor.
  class Fetcher
    include Celluloid
    include Sidekiq::Util

    TIMEOUT = 1

    def initialize(mgr, queues)
      @cmd = queues.map { |q| "queue:#{q}" }
      @mgr = mgr

      # One second timeout for blpop.
      @cmd << TIMEOUT
    end

    # Fetching is straightforward: the Manager makes a fetch
    # request for each idle processor when Sidekiq starts and
    # then issues a new fetch request every time a Processor
    # finishes a message.
    #
    # Because we have to shut down cleanly, we can't block
    # forever and we can't loop forever.  Instead we reschedule
    # a new fetch if the current fetch turned up nothing.
    def fetch
      watchdog('Fetcher#fetch died') do
        queue = nil
        msg = nil
        Sidekiq.redis { |conn| (queue, msg) = conn.blpop(*@cmd) }

        if msg
          @mgr.assign!(msg, queue.gsub(/.*queue:/, ''))
        else
          after(0) { fetch }
        end
      end
    end

  end
end
