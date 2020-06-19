# frozen_string_literal: true

require "sidekiq/util"
require "sidekiq/fetch"
require "sidekiq/job_logger"
require "sidekiq/job_retry"

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

    def initialize(mgr, options)
      @mgr = mgr
      @down = false
      @done = false
      @job = nil
      @thread = nil
      @strategy = options[:fetch]
      @reloader = options[:reloader] || proc { |&block| block.call }
      @job_logger = (options[:job_logger] || Sidekiq::JobLogger).new
      @retrier = Sidekiq::JobRetry.new
    end

    def terminate(wait = false)
      @done = true
      return unless @thread
      @thread.value if wait
    end

    def kill(wait = false)
      @done = true
      return unless @thread
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
      process_one until @done
      @mgr.processor_stopped(self)
    rescue Sidekiq::Shutdown
      @mgr.processor_stopped(self)
    rescue Exception => ex
      @mgr.processor_died(self, ex)
    end

    def process_one
      @job = fetch
      process(@job) if @job
      @job = nil
    end

    def get_one
      work = @strategy.retrieve_work
      if @down
        logger.info { "Redis is online, #{::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - @down} sec downtime" }
        @down = nil
      end
      work
    rescue Sidekiq::Shutdown
    rescue => ex
      handle_fetch_exception(ex)
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
      unless @down
        @down = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
        logger.error("Error fetching job: #{ex}")
        handle_exception(ex)
      end
      sleep(1)
      nil
    end

    def dispatch(job_hash, queue, jobstr)
      # since middleware can mutate the job hash
      # we need to clone it to report the original
      # job structure to the Web UI
      # or to push back to redis when retrying.
      # To avoid costly and, most of the time, useless cloning here,
      # we pass original String of JSON to respected methods
      # to re-parse it there if we need access to the original, untouched job

      @job_logger.prepare(job_hash) do
        @retrier.global(jobstr, queue) do
          @job_logger.call(job_hash, queue) do
            stats(jobstr, queue) do
              # Rails 5 requires a Reloader to wrap code execution.  In order to
              # constantize the worker and instantiate an instance, we have to call
              # the Reloader.  It handles code loading, db connection management, etc.
              # Effectively this block denotes a "unit of work" to Rails.
              @reloader.call do
                klass = constantize(job_hash["class"])
                worker = klass.new
                worker.jid = job_hash["jid"]
                @retrier.local(worker, jobstr, queue) do
                  yield worker
                end
              end
            end
          end
        end
      end
    end

    def process(work)
      jobstr = work.job
      queue = work.queue_name

      # Treat malformed JSON as a special case: job goes straight to the morgue.
      job_hash = nil
      begin
        job_hash = Sidekiq.load_json(jobstr)
      rescue => ex
        handle_exception(ex, {context: "Invalid JSON for job", jobstr: jobstr})
        # we can't notify because the job isn't a valid hash payload.
        DeadSet.new.kill(jobstr, notify_failure: false)
        return work.acknowledge
      end

      ack = false
      begin
        dispatch(job_hash, queue, jobstr) do |worker|
          Sidekiq.server_middleware.invoke(worker, job_hash, queue) do
            execute_job(worker, job_hash["args"])
          end
        end
        ack = true
      rescue Sidekiq::Shutdown
        # Had to force kill this job because it didn't finish
        # within the timeout.  Don't acknowledge the work since
        # we didn't properly finish it.
      rescue Sidekiq::JobRetry::Handled => h
        # this is the common case: job raised error and Sidekiq::JobRetry::Handled
        # signals that we created a retry successfully.  We can acknowlege the job.
        ack = true
        e = h.cause || h
        handle_exception(e, {context: "Job raised exception", job: job_hash, jobstr: jobstr})
        raise e
      rescue Exception => ex
        # Unexpected error!  This is very bad and indicates an exception that got past
        # the retry subsystem (e.g. network partition).  We won't acknowledge the job
        # so it can be rescued when using Sidekiq Pro.
        handle_exception(ex, {context: "Internal exception!", job: job_hash, jobstr: jobstr})
        raise ex
      ensure
        if ack
          # We don't want a shutdown signal to interrupt job acknowledgment.
          Thread.handle_interrupt(Sidekiq::Shutdown => :never) do
            work.acknowledge
          end
        end
      end
    end

    def execute_job(worker, cloned_args)
      worker.perform(*cloned_args)
    end

    # Ruby doesn't provide atomic counters out of the box so we'll
    # implement something simple ourselves.
    # https://bugs.ruby-lang.org/issues/14706
    class Counter
      def initialize
        @value = 0
        @lock = Mutex.new
      end

      def incr(amount = 1)
        @lock.synchronize { @value += amount }
      end

      def reset
        @lock.synchronize {
          val = @value
          @value = 0
          val
        }
      end
    end

    # jruby's Hash implementation is not threadsafe, so we wrap it in a mutex here
    class SharedWorkerState
      def initialize
        @worker_state = {}
        @lock = Mutex.new
      end

      def set(tid, hash)
        @lock.synchronize { @worker_state[tid] = hash }
      end

      def delete(tid)
        @lock.synchronize { @worker_state.delete(tid) }
      end

      def dup
        @lock.synchronize { @worker_state.dup }
      end

      def size
        @lock.synchronize { @worker_state.size }
      end

      def clear
        @lock.synchronize { @worker_state.clear }
      end
    end

    PROCESSED = Counter.new
    FAILURE = Counter.new
    WORKER_STATE = SharedWorkerState.new

    def stats(jobstr, queue)
      WORKER_STATE.set(tid, {queue: queue, payload: jobstr, run_at: Time.now.to_i})

      begin
        yield
      rescue Exception
        FAILURE.incr
        raise
      ensure
        WORKER_STATE.delete(tid)
        PROCESSED.incr
      end
    end

    def constantize(str)
      return Object.const_get(str) unless str.include?("::")

      names = str.split("::")
      names.shift if names.empty? || names.first.empty?

      names.inject(Object) do |constant, name|
        # the false flag limits search for name to under the constant namespace
        #   which mimics Rails' behaviour
        constant.const_get(name, false)
      end
    end
  end
end
