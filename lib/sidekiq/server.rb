require 'celluloid'
require 'redis'
require 'multi_json'

require 'sidekiq/worker'

module Sidekiq

  ##
  # This is the main router in the system.  This
  # manages the worker state and fetches messages
  # from Redis to be dispatched to ready workers.
  #
  class Server
    include Util
    include Celluloid

    trap_exit :worker_died

    def initialize(location, options={})
      log "Starting sidekiq #{Sidekiq::VERSION} with Redis at #{location}"
      verbose options.inspect
      @count = options[:worker_count]
      @queues = options[:queues]
      @queue_idx = 0
      @queues_size = @queues.size
      @redis = Redis.new(:host => options[:redis_host], :port => options[:redis_port])

      @done = false
      @busy = []
      @ready = []
      @count.times do
        @ready << Worker.new_link
      end
    end

    def stop
      @done = true
      @ready.each(&:terminate)
      @ready.clear

      after(30) do
        @busy.each(&:terminate)
        terminate
      end
    end

    def start
      dispatch
    end

    def worker_done(worker)
      @busy.delete(worker)
      if stopped?
        worker.terminate
      else
        @ready << worker
      end
      dispatch
    end

    def worker_died(worker, reason)
      @busy.delete(worker)
      log "Worker death: #{reason}"
      log reason.backtrace.join("\n") if reason

      unless stopped?
        @ready << Worker.new_link 
        dispatch
      end
    end

    private

    def dispatch
      watchdog("Fatal error in sidekiq, dispatch loop died") do
        return if stopped?

        # Our dispatch loop
        queue_idx = 0
        none_found = true
        loop do
          # return so that we don't dispatch again until worker_done
          return if @ready.size == 0

          current_queue = @queues[queue_idx]
          msg = @redis.lpop("queue:#{current_queue}")
          if msg
            worker = @ready.pop
            @busy << worker
            worker.process! MultiJson.decode(msg)
            none_found = false
          end

          queue_idx += 1

          # Loop through the queues, looking for a message in each.
          # if we find no messages in any of the queues, we can break
          # out of the loop.  Otherwise we loop again.
          lastq = (queue_idx % @queues.size == 0)
          if lastq && none_found
            break
          elsif lastq
            queue_idx = 0
            none_found = true
          end
        end

        after(1) { dispatch }
      end
    end

    def stopped?
      @done
    end
  end
end
