# encoding: utf-8
require 'sidekiq/util'
require 'sidekiq/processor'
require 'sidekiq/fetch'

module Sidekiq

  ##
  # The Manager is the central coordination point in Sidekiq, controlling
  # the lifecycle of the Processors and feeding them jobs as necessary.
  #
  # Tasks:
  #
  # 1. start: Spin up Processors.  Issue fetch requests for each.
  # 2. processor_done: Handle job success, issue fetch request.
  # 3. processor_died: Handle job failure, throw away Processor, issue fetch request.
  # 4. quiet: shutdown idle Processors, ignore further fetch requests.
  # 5. stop: hard stop the Processors by deadline.
  #
  # Note that only the last task requires a Thread since it has to monitor
  # the shutdown process.  The other tasks are performed by other threads.
  #
  class Manager
    include Util

    attr_writer :fetcher
    attr_reader :in_progress
    attr_reader :ready

    SPIN_TIME_FOR_GRACEFUL_SHUTDOWN = 1

    def initialize(condvar, options={})
      logger.debug { options.inspect }
      @options = options
      @count = options[:concurrency] || 25
      raise ArgumentError, "Concurrency of #{@count} is not supported" if @count < 1
      @finished = condvar

      @in_progress = {}
      @done = false
      @ready = Array.new(@count) do
        Processor.new(self)
      end
      @plock = Mutex.new
    end

    def start
      @ready.each do |x|
        x.start
        dispatch
      end
    end

    def quiet
      return if @done

      @done = true

      logger.info { "Terminating quiet workers" }

      @plock.synchronize do
        @ready.each { |x| x.terminate }
        @ready.clear
      end
    end

    def stop(deadline)
      quiet
      return if @in_progress.empty?

      logger.info { "Pausing to allow workers to finish..." }
      remaining = deadline - Time.now
      while remaining > 0.5
        return if @in_progress.empty?
        sleep 0.5
        remaining = deadline - Time.now
      end
      return if @in_progress.empty?

      hard_shutdown
    end

    def processor_done(processor)
      @plock.synchronize do
        @in_progress.delete(processor)
        if @done
          processor.terminate
          #shutdown if @in_progress.empty?
        else
          @ready << processor
        end
      end
      dispatch
    end

    def processor_died(processor, reason)
      @plock.synchronize do
        @in_progress.delete(processor)
        if @done
          #shutdown if @in_progress.empty?
        else
          p = Processor.new(self)
          p.start
          @ready << p
        end
      end
      dispatch
    end

    def assign(work)
      if @done
        # Race condition between Manager#stop if Fetcher
        # is blocked on redis and gets a message after
        # all the ready Processors have been stopped.
        # Push the message back to redis.
        work.requeue
      else
        processor = nil
        @plock.synchronize do
          processor = @ready.pop
          @in_progress[processor] = work
        end
        processor.request_process(work)
      end
    end

    def stopped?
      @done
    end

    private

    def hard_shutdown
      # We've reached the timeout and we still have busy workers.
      # They must die but their jobs shall live on.
      cleanup = nil
      @plock.synchronize do
        cleanup = @in_progress.dup
      end

      if cleanup.size > 0
        logger.warn { "Terminating #{cleanup.size} busy worker threads" }
        logger.warn { "Work still in progress #{cleanup.values.inspect}" }
        # Re-enqueue unfinished jobs
        # NOTE: You may notice that we may push a job back to redis before
        # the worker thread is terminated. This is ok because Sidekiq's
        # contract says that jobs are run AT LEAST once. Process termination
        # is delayed until we're certain the jobs are back in Redis because
        # it is worse to lose a job than to run it twice.
        Sidekiq::Fetcher.strategy.bulk_requeue(cleanup.values, @options)
      end

      cleanup.each do |processor, _|
        processor.kill
      end
    end

    def dispatch
      return if @done
      # This is a safety check to ensure we haven't leaked processors somehow.
      raise "BUG: No processors, cannot continue!" if @ready.empty? && @in_progress.empty?
      raise "No ready processor!?" if @ready.empty?

      @fetcher.request_job
    end

  end
end
