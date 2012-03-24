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

    def initialize(mgr, queues)
      @cmd = queues.map { |q| "queue:#{q}" }
      @mgr = mgr

      # One second timeout for blpop.
      # We can't block forever or else we can't shut down
      # properly.
      @cmd << 1
    end

    def fetch
      watchdog('Fetcher#fetch died') do

        msg = nil
        Sidekiq.redis do |conn|
          a = Time.now
          (queue, msg) = conn.blpop *@cmd
          p [Time.now - a, queue, msg]
          @mgr.assign! msg, queue.gsub(/\Aqueue:/, '') if msg
        end
        after(0) { fetch } unless msg

      end
    end

  end
end
