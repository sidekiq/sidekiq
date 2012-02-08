require 'celluloid'
require 'redis'
require 'multi_json'

require 'sidekiq/util'
require 'sidekiq/processor'

module Sidekiq

  ##
  # The main router in the system.  This
  # manages the processor state and fetches messages
  # from Redis to be dispatched to an idle processor.
  #
  class Manager
    include Util
    include Celluloid

    trap_exit :processor_died

    def initialize(redis, options={})
      log "Booting sidekiq #{Sidekiq::VERSION} with Redis at #{redis.client.location}"
      verbose options.inspect
      @count = options[:processor_count] || 25
      @queues = options[:queues]
      @queue_idx = 0
      @queues_size = @queues.size
      @redis = redis
      @done_callback = nil

      @done = false
      @busy = []
      @ready = []
      @count.times do
        @ready << Processor.new_link(current_actor)
      end
    end

    def stop
      @done = true
      @ready.each(&:terminate)
      @ready.clear

      after(5) do
        signal(:shutdown)
      end
    end

    def start
      dispatch(true)
    end

    def when_done
      @done_callback = Proc.new
    end

    def processor_done(processor)
      @done_callback.call(processor) if @done_callback
      @busy.delete(processor)
      if stopped?
        processor.terminate
      else
        @ready << processor
      end
      dispatch
    end

    def processor_died(processor, reason)
      @busy.delete(processor)

      if reason
        log "Processor death: #{reason}"
        log reason.backtrace.join("\n")
      end

      unless stopped?
        @ready << Processor.new_link(current_actor)
        dispatch
      end
    end

    private

    def find_work(queue_idx)
      current_queue = @queues[queue_idx]
      msg = @redis.lpop("queue:#{current_queue}")
      if msg
        processor = @ready.pop
        @busy << processor
        processor.process!(MultiJson.decode(msg))
      end
      !!msg
    end

    def dispatch(schedule = false)
      watchdog("Fatal error in sidekiq, dispatch loop died") do
        return if stopped?

        # Our dispatch loop
        # Loop through the queues, looking for a message in each.
        queue_idx = 0
        found = false
        loop do
          # return so that we don't dispatch again until processor_done
          break verbose('no processors') if @ready.size == 0

          found ||= find_work(queue_idx)
          queue_idx += 1

          # if we find no messages in any of the queues, we can break
          # out of the loop.  Otherwise we loop again.
          lastq = (queue_idx % @queues.size == 0)
          if lastq && !found
            verbose('nothing to process'); break
          elsif lastq
            queue_idx = 0
            found = false
          end
        end

        # This is the polling loop that ensures we check Redis every
        # second for work, even if there was nothing to do this time
        # around.
        after(1) { verbose('ping'); dispatch(schedule) } if schedule
      end
    end

    def stopped?
      @done
    end
  end
end
