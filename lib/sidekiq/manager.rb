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

    def initialize(options={})
      logger.info "Booting sidekiq #{Sidekiq::VERSION} with Redis at #{redis.client.location}"
      logger.debug { options.inspect }
      @count = options[:concurrency] || 25
      @queues = options[:queues]
      @done_callback = nil

      @done = false
      @busy = []
      @ready = @count.times.map { Processor.new_link(current_actor) }
    end

    def stop(options={})
      shutdown = options[:shutdown]
      timeout = options[:timeout]

      @done = true
      @ready.each { |x| x.terminate if x.alive? }
      @ready.clear

      redis.with_connection do |conn|
        workers = conn.smembers('workers')
        workers.each do |name|
          conn.srem('workers', name) if name =~ /:#{process_id}-/
        end
      end

      if shutdown
        if @busy.empty?
          # after(0) needed to avoid deadlock in Celluoid after USR1 + TERM
          return after(0) { signal(:shutdown) }
        else
          logger.info { "Pausing #{timeout} seconds to allow workers to finish..." }
        end

        after(timeout) do
          @busy.each { |x| x.terminate if x.alive? }
          signal(:shutdown)
        end
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
          processor.terminate if processor.alive?
          signal(:shutdown) if @busy.empty?
        else
          @ready << processor if processor.alive?
        end
        dispatch
      end
    end

    def processor_died(processor, reason)
      @busy.delete(processor)

      unless stopped?
        @ready << Processor.new_link(current_actor)
        dispatch
      else
        signal(:shutdown) if @busy.empty?
      end
    end

    private

    def find_work(queue)
      msg = redis.lpop("queue:#{queue}")
      if msg
        processor = @ready.pop
        @busy << processor
        processor.process!(MultiJson.decode(msg), queue)
      end
      !!msg
    end

    def dispatch(schedule = false)
      watchdog("Fatal error in sidekiq, dispatch loop died") do
        return if stopped?

        # This is a safety check to ensure we haven't leaked
        # processors somehow.
        raise "BUG: No processors, cannot continue!" if @ready.empty? && @busy.empty?

        # Dispatch loop
        loop do
          break logger.debug('no processors') if @ready.empty?
          found = false
          @ready.size.times do
            found ||= find_work(@queues.sample)
          end
          break logger.debug('nothing to process') unless found
        end

        # This is the polling loop that ensures we check Redis every
        # second for work, even if there was nothing to do this time
        # around.
        after(1) do
          dispatch(schedule)
        end if schedule
      end
    end

    def stopped?
      @done
    end
  end
end
