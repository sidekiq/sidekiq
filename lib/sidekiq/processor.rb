require 'sidekiq/util'
require 'sidekiq/fetch'
require 'thread'
require 'concurrent/map'
require 'concurrent/atomic/atomic_fixnum'

module Sidekiq
  ##
  # The Processor is a standalone thread which:
  #
  # 1. fetches a job from Redis
  # 2. executes the job
  #   a. instantiate the Worker
  #   b. run the middleware chain
  #   c. call #perform
  #
  # A Processor can exit due to shutdown (processor_stopped)
  # or due to an error during job execution (processor_died)
  #
  # If an error occurs in the job execution, the
  # Processor calls the Manager to create a new one
  # to replace itself and exits.
  #
  class Processor

    include Util

    attr_reader :thread
    attr_reader :job

    def initialize(mgr)
      @mgr = mgr
      @down = false
      @done = false
      @job = nil
      @thread = nil
      @strategy = (mgr.options[:fetch] || Sidekiq::BasicFetch).new(mgr.options)
    end

    def terminate(wait=false)
      @done = true
      return if !@thread
      @thread.value if wait
    end

    def kill(wait=false)
      @done = true
      return if !@thread
      # unlike the other actors, terminate does not wait
      # for the thread to finish because we don't know how
      # long the job will take to finish.  Instead we
      # provide a `kill` method to call after the shutdown
      # timeout passes.
      @thread.raise ::Sidekiq::Shutdown
      @thread.value if wait
    end

    def start
      @thread ||= safe_thread("processor", &method(:run))
    end

    private unless $TESTING

    def run
      begin
        while !@done
          process_one
        end
        @mgr.processor_stopped(self)
      rescue Sidekiq::Shutdown
        @mgr.processor_stopped(self)
      rescue Exception => ex
        @mgr.processor_died(self, ex)
      end
    end

    def process_one
      @job = fetch
      process(@job) if @job
      @job = nil
    end

    def get_one
      begin
        work = @strategy.retrieve_work
        (logger.info { "Redis is online, #{Time.now - @down} sec downtime" }; @down = nil) if @down
        work
      rescue Sidekiq::Shutdown
      rescue => ex
        handle_fetch_exception(ex)
      end
    end

    def fetch
      j = get_one
      if j && @done
        j.requeue
        nil
      else
        j
      end
    end

    def handle_fetch_exception(ex)
      if !@down
        @down = Time.now
        logger.error("Error fetching job: #{ex}")
        ex.backtrace.each do |bt|
          logger.error(bt)
        end
      end
      sleep(1)
    end

    def process(work)
      jobstr = work.job
      queue = work.queue_name

      ack = false
      begin
        job = Sidekiq.load_json(jobstr)
        klass  = job['class'.freeze].constantize
        worker = klass.new
        worker.jid = job['jid'.freeze]

        stats(worker, job, queue) do
          Sidekiq.server_middleware.invoke(worker, job, queue) do
            # Only ack if we either attempted to start this job or
            # successfully completed it. This prevents us from
            # losing jobs if a middleware raises an exception before yielding
            ack = true
            execute_job(worker, cloned(job['args'.freeze]))
          end
        end
        ack = true
      rescue Sidekiq::Shutdown
        # Had to force kill this job because it didn't finish
        # within the timeout.  Don't acknowledge the work since
        # we didn't properly finish it.
        ack = false
      rescue Exception => ex
        handle_exception(ex, job || { :job => jobstr })
        raise
      ensure
        work.acknowledge if ack
      end
    end

    def execute_job(worker, cloned_args)
      worker.perform(*cloned_args)
    end

    def thread_identity
      @str ||= Thread.current.object_id.to_s(36)
    end

    WORKER_STATE = Concurrent::Map.new
    PROCESSED = Concurrent::AtomicFixnum.new
    FAILURE = Concurrent::AtomicFixnum.new

    def stats(worker, job, queue)
      tid = thread_identity
      WORKER_STATE[tid] = {:queue => queue, :payload => job, :run_at => Time.now.to_i }

      begin
        yield
      rescue Exception
        FAILURE.increment
        raise
      ensure
        WORKER_STATE.delete(tid)
        PROCESSED.increment
      end
    end

    # Deep clone the arguments passed to the worker so that if
    # the job fails, what is pushed back onto Redis hasn't
    # been mutated by the worker.
    def cloned(ary)
      Marshal.load(Marshal.dump(ary))
    end

  end
end
