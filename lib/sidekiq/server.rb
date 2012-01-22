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
      @count = options[:worker_count]
      @queues = options[:queues]
      @queue_idx = 0
      @queues_size = @queues.size
      @redis = Redis.new(location)

      start
      dispatch
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
      @done = false
      @busy = []
      @ready = []
      @count.times do
        @ready << Worker.new_link
      end
    end

    def worker_done(worker)
      @busy.remove(worker)
      if stopped?
        worker.terminate
      else
        @ready << worker
      end
      dispatch
    end

    def worker_died(worker, reason)
      @busy.remove(worker)
      @ready << Worker.new_link unless stopped?
      log "Worker death: #{reason}"
      log reason.backtrace.join("\n")
    end

    def dispatch
      watchdog("Fatal error in sidekiq, dispatch loop died") do
        return if stopped?

        # Our dispatch loop
        queue_idx = 0
        none_found = true
        loop do
          break if @ready.size == 0

          queue_idx += 1

          # we loop through the queues, looking for a message in each.
          # if we find no messages in any of the queues, we can break
          # out of the loop.  Otherwise we loop again.
          if (queue_idx % @queues.size == 0) && none_found
            break
          else
            queue_idx = 0
            none_found = true
          end

          current_queue = @queues[queue_idx]
          msg = redis.lpop("queue:#{current_queue}")
          if msg
            @busy << worker = @ready.pop
            worker.process! MultiJson.decode(msg)
            none_found = false
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
