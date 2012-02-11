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
      @redis = redis
      @done_callback = nil

      @done = false
      @busy = []
      @ready = @count.times.map { Processor.new_link(current_actor) }
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

    def when_done(&blk)
      @done_callback = blk
    end

    def processor_done(processor)
      watchdog('sidekiq processor_done crashed!') do
        @done_callback.call(processor) if @done_callback
        @busy.delete(processor)
        if stopped?
          processor.terminate
        else
          @ready << processor
        end
        dispatch
      end
    end

    def processor_died(processor, reason)
      @busy.delete(processor)

      if reason
        err "Processor death: #{reason}"
        err reason.backtrace.join("\n")
      end

      unless stopped?
        @ready << Processor.new_link(current_actor)
        dispatch
      end
    end

    private

    def find_work(queue)
      msg = @redis.lpop("queue:#{queue}")
      if msg
        processor = @ready.pop
        @busy << processor
        processor.process!(MultiJson.decode(msg), current_queue)
      end
      !!msg
    end

    def dispatch(schedule = false)
      watchdog("Fatal error in sidekiq, dispatch loop died") do
        return if stopped?

        # Dispatch loop
        loop do
          break verbose('no processors') if @ready.empty?
          found = false
          @ready.size.times do
            found ||= find_work(@queues.sample)
          end
          break verbose('nothing to process') unless found
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
