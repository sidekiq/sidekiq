require 'celluloid'

require 'sidekiq/util'
require 'sidekiq/processor'
require 'sidekiq/fetch'

module Sidekiq

  ##
  # The main router in the system.  This
  # manages the processor state and accepts messages
  # from Redis to be dispatched to an idle processor.
  #
  class Manager
    include Util
    include Celluloid

    trap_exit :processor_died

    def initialize(options={})
      logger.debug { options.inspect }
      @count = options[:concurrency] || 25
      @done_callback = nil

      @in_progress = {}
      @done = false
      @busy = []
      @fetcher = Fetcher.new(current_actor, options[:queues], !!options[:strict])
      @ready = @count.times.map { Processor.new_link(current_actor) }
      procline
    end

    def stop(options={})
      watchdog('Manager#stop died') do
        shutdown = options[:shutdown]
        timeout = options[:timeout]

        @done = true
        Sidekiq::Fetcher.done!
        @fetcher.terminate! if @fetcher.alive?

        logger.info { "Shutting down #{@ready.size} quiet workers" }
        @ready.each { |x| x.terminate if x.alive? }
        @ready.clear

        logger.debug { "Clearing workers in redis" }
        Sidekiq.redis do |conn|
          workers = conn.smembers('workers')
          workers.each do |name|
            conn.srem('workers', name) if name =~ /:#{process_id}-/
          end
        end

        return after(0) { signal(:shutdown) } if @busy.empty?
        logger.info { "Pausing up to #{timeout} seconds to allow workers to finish..." }
        hard_shutdown_in timeout if shutdown
      end
    end

    def start
      @ready.each { dispatch }
    end

    def when_done(&blk)
      @done_callback = blk
    end

    def processor_done(processor)
      watchdog('Manager#processor_done died') do
        @done_callback.call(processor) if @done_callback
        @in_progress.delete(processor.object_id)
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
      watchdog("Manager#processor_died died") do
        @in_progress.delete(processor.object_id)
        @busy.delete(processor)

        unless stopped?
          @ready << Processor.new_link(current_actor)
          dispatch
        else
          signal(:shutdown) if @busy.empty?
        end
      end
    end

    def assign(msg, queue)
      watchdog("Manager#assign died") do
        if stopped?
          # Race condition between Manager#stop if Fetcher
          # is blocked on redis and gets a message after
          # all the ready Processors have been stopped.
          # Push the message back to redis.
          Sidekiq.redis do |conn|
            conn.lpush("queue:#{queue}", msg)
          end
        else
          processor = @ready.pop
          @in_progress[processor.object_id] = [msg, queue]
          @busy << processor
          processor.process!(msg, queue)
        end
      end
    end

    private

    def hard_shutdown_in(delay)
      after(delay) do
        watchdog("Manager#watch_for_shutdown died") do
          # We've reached the timeout and we still have busy workers.
          # They must die but their messages shall live on.
          logger.info("Still waiting for #{@busy.size} busy workers")

          Sidekiq.redis do |conn|
            @busy.each do |processor|
              # processor is an actor proxy and we can't call any methods
              # that would go to the actor (since it's busy).  Instead
              # we'll use the object_id to track the worker's data here.
              processor.terminate if processor.alive?
              msg, queue = @in_progress[processor.object_id]
              conn.lpush("queue:#{queue}", msg)
            end
          end
          logger.info("Pushed #{@busy.size} messages back to Redis")

          after(0) { signal(:shutdown) }
        end
      end
    end

    def dispatch
      return if stopped?
      # This is a safety check to ensure we haven't leaked
      # processors somehow.
      raise "BUG: No processors, cannot continue!" if @ready.empty? && @busy.empty?
      raise "No ready processor!?" if @ready.empty?

      @fetcher.fetch!
    end

    def stopped?
      @done
    end

    def procline
      $0 = "sidekiq #{Sidekiq::VERSION} [#{@busy.size} of #{@count} busy]#{stopped? ? ' stopping' : ''}"
      after(5) { procline }
    end
  end
end
