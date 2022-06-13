# frozen_string_literal: true

require "sidekiq/fetch"
require "sidekiq/job_logger"
require "sidekiq/job_retry"

module Sidekiq
  ##
  # The Processor is a standalone thread which:
  #
  # 1. fetches a job from Redis
  # 2. executes the job
  #   a. instantiate the job class
  #   b. run the middleware chain
  #   c. call #perform
  #
  # A Processor can exit due to shutdown or due to
  # an error during job execution.
  #
  # If an error occurs in the job execution, the
  # Processor calls the Manager to create a new one
  # to replace itself and exits.
  #
  class Processor
    include Sidekiq::Component

    attr_reader :thread
    attr_reader :job

    def initialize(options, &block)
      @callback = block
      @down = false
      @done = false
      @job = nil
      @thread = nil
      @config = options
      @strategy = options[:fetch]
      @reloader = options[:reloader] || proc { |&block| block.call }
      @job_logger = (options[:job_logger] || Sidekiq::JobLogger).new
      @retrier = Sidekiq::JobRetry.new(options)
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
      @callback.call(self)
    rescue Sidekiq::Shutdown
      @callback.call(self)
    rescue Exception => ex
      @callback.call(self, ex)
    end

    def process_one(&block)
      @job = fetch
      process(@job) if @job
      @job = nil
    end

    def get_one
      uow = @strategy.retrieve_work
      if @down
        logger.info { "Redis is online, #{::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - @down} sec downtime" }
        @down = nil
      end
      uow
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
            stats(jobstr, queue, job_hash["wrapped"] || job_hash["class"]) do
              # Rails 5 requires a Reloader to wrap code execution.  In order to
              # constantize the worker and instantiate an instance, we have to call
              # the Reloader.  It handles code loading, db connection management, etc.
              # Effectively this block denotes a "unit of work" to Rails.
              @reloader.call do
                klass = constantize(job_hash["class"])
                inst = klass.new
                inst.jid = job_hash["jid"]
                @retrier.local(inst, jobstr, queue) do
                  yield inst
                end
              end
            end
          end
        end
      end
    end

    def process(uow)
      jobstr = uow.job
      queue = uow.queue_name

      # Treat malformed JSON as a special case: job goes straight to the morgue.
      job_hash = nil
      begin
        job_hash = Sidekiq.load_json(jobstr)
      rescue => ex
        handle_exception(ex, {context: "Invalid JSON for job", jobstr: jobstr})
        # we can't notify because the job isn't a valid hash payload.
        DeadSet.new.kill(jobstr, notify_failure: false)
        return uow.acknowledge
      end

      ack = false
      begin
        dispatch(job_hash, queue, jobstr) do |inst|
          @config.server_middleware.invoke(inst, job_hash, queue) do
            execute_job(inst, job_hash["args"])
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
            uow.acknowledge
          end
        end
      end
    end

    def execute_job(inst, cloned_args)
      inst.perform(*cloned_args)
    end

    # jruby's Hash implementation is not threadsafe, so we wrap it in a mutex here
    class SharedWorkState
      def initialize
        @work_state = {}
        @lock = Mutex.new
      end

      def set(tid, hash)
        @lock.synchronize { @work_state[tid] = hash }
      end

      def delete(tid)
        @lock.synchronize { @work_state.delete(tid) }
      end

      def dup
        @lock.synchronize { @work_state.dup }
      end

      def size
        @lock.synchronize { @work_state.size }
      end

      def clear
        @lock.synchronize { @work_state.clear }
      end
    end

    class ExecutionTracker
      def initialize
        @queues = Hash.new(0)
        @jobs = Hash.new(0)
        @totals = Hash.new(0)
        @lock = Mutex.new
      end

      # We track success/failure and time per class and per queue.
      # "q:default|ms" => 1755 means 1755ms executing jobs from the default queue
      # "Foo::SomeJob|f" => 5 means Foo::SomeJob failed 5 times
      #
      # All of these values are rolled up into one "exec" Hash per day in Redis:
      # "exec:2022-07-06", etc by the heartbeat.
      def track(queue, klass)
        start = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC, :millisecond)
        time_ms = 0
        begin
          begin
            yield
          ensure
            finish = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC, :millisecond)
            time_ms = finish - start
          end
        rescue Exception
          @lock.synchronize {
            @queues["#{queue}|f"] += 1
            @jobs["#{klass}|f"] += 1
            @totals["f"] += 1
          }
          raise
        ensure
          @lock.synchronize {
            @queues["#{queue}|ms"] += time_ms
            @queues["#{queue}|p"] += 1

            @jobs["#{klass}|ms"] += time_ms
            @jobs["#{klass}|p"] += 1

            @totals["ms"] += time_ms
            @totals["p"] += 1
          }
        end
      end

      def reset
        @lock.synchronize {
          array = [@totals, @queues, @jobs]
          @totals = Hash.new(0)
          @queues = Hash.new(0)
          @jobs = Hash.new(0)
          array
        }
      end
    end

    PROCESSED = ExecutionTracker.new
    WORK_STATE = SharedWorkState.new

    def stats(jobstr, queue, klass, &block)
      WORK_STATE.set(tid, {queue: queue, payload: jobstr, run_at: Time.now.to_i})

      begin
        PROCESSED.track(queue, klass, &block)
      ensure
        WORK_STATE.delete(tid)
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
