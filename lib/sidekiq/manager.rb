require 'sidekiq/util'
require 'sidekiq/actor'
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
    include Actor
    trap_exit :processor_died

    attr_reader :ready
    attr_reader :busy
    attr_accessor :fetcher

    def initialize(options={})
      logger.debug { options.inspect }
      @count = options[:concurrency] || 25
      @done_callback = nil

      @in_progress = {}
      @threads = {}
      @done = false
      @busy = []
      @fetcher = Fetcher.new(current_actor, options)
      @ready = @count.times.map do
        p = Processor.new_link(current_actor)
        p.proxy_id = p.object_id
        p
      end
    end

    def stop(options={})
      watchdog('Manager#stop died') do
        shutdown = options[:shutdown]
        timeout = options[:timeout]

        @done = true
        Sidekiq::Fetcher.done!
        @fetcher.async.terminate if @fetcher.alive?

        logger.info { "Shutting down #{@ready.size} quiet workers" }
        @ready.each { |x| x.terminate if x.alive? }
        @ready.clear

        clear_worker_set

        return after(0) { signal(:shutdown) } if @busy.empty?
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
        @threads.delete(processor.object_id)
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
        @threads.delete(processor.object_id)
        @busy.delete(processor)

        unless stopped?
          p = Processor.new_link(current_actor)
          p.proxy_id = p.object_id
          @ready << p
          dispatch
        else
          signal(:shutdown) if @busy.empty?
        end
      end
    end

    def assign(work)
      watchdog("Manager#assign died") do
        if stopped?
          # Race condition between Manager#stop if Fetcher
          # is blocked on redis and gets a message after
          # all the ready Processors have been stopped.
          # Push the message back to redis.
          work.requeue
        else
          processor = @ready.pop
          @in_progress[processor.object_id] = work
          @busy << processor
          processor.async.process(work)
        end
      end
    end

    # A hack worthy of Rube Goldberg.  We need to be able
    # to hard stop a working thread.  But there's no way for us to
    # get handle to the underlying thread performing work for a processor
    # so we have it call us and tell us.
    def real_thread(proxy_id, thr)
      @threads[proxy_id] = thr
    end

    def procline(tag)
      "sidekiq #{Sidekiq::VERSION} #{tag}[#{@busy.size} of #{@count} busy]#{stopped? ? ' stopping' : ''}"
    end

    private

    def clear_worker_set
      # Clearing workers in Redis
      # NOTE: we do this before terminating worker threads because the
      # process will likely receive a hard shutdown soon anyway, which
      # means the threads will killed.
      logger.debug { "Clearing workers in redis" }
      Sidekiq.redis do |conn|
        workers = conn.smembers('workers')
        workers_to_remove = workers.select do |worker_name|
          worker_name =~ /:#{process_id}-/
        end
        conn.srem('workers', workers_to_remove) if !workers_to_remove.empty?
      end
    rescue => ex
      Sidekiq.logger.warn("Unable to clear worker set while shutting down: #{ex.message}")
    end

    def hard_shutdown_in(delay)
      logger.info { "Pausing up to #{delay} seconds to allow workers to finish..." }

      after(delay) do
        watchdog("Manager#hard_shutdown_in died") do
          # We've reached the timeout and we still have busy workers.
          # They must die but their messages shall live on.
          logger.info("Still waiting for #{@busy.size} busy workers")

          # Re-enqueue terminated jobs
          # NOTE: You may notice that we may push a job back to redis before
          # the worker thread is terminated. This is ok because Sidekiq's
          # contract says that jobs are run AT LEAST once. Process termination
          # is delayed until we're certain the jobs are back in Redis because
          # it is worse to lose a job than to run it twice.
          Sidekiq::Fetcher.strategy.bulk_requeue(@in_progress.values)

          logger.debug { "Terminating #{@busy.size} busy worker threads" }
          @busy.each do |processor|
            if processor.alive? && t = @threads.delete(processor.object_id)
              t.raise Shutdown
            end
          end

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

      @fetcher.async.fetch
    end

    def stopped?
      @done
    end
  end
end
