require 'sidekiq/util'

require 'sidekiq/middleware/server/retry_jobs'
require 'sidekiq/middleware/server/logging'

module Sidekiq
  ##
  # The Processor receives a message from the Manager and actually
  # processes it.  It instantiates the worker, runs the middleware
  # chain and then calls Sidekiq::Worker#perform.
  class Processor
    # To prevent a memory leak, ensure that stats expire. However, they
    # should take up a minimal amount of storage so keep them around
    # for a long time.
    STATS_TIMEOUT = 24 * 60 * 60 * 365 * 5

    include Util

    def self.default_middleware
      Middleware::Chain.new do |m|
        m.add Middleware::Server::Logging
        m.add Middleware::Server::RetryJobs
        if defined?(::ActiveRecord::Base)
          require 'sidekiq/middleware/server/active_record'
          m.add Sidekiq::Middleware::Server::ActiveRecord
        end
      end
    end

    attr_reader :thread

    def initialize(mgr)
      @mgr = mgr
      @done = false
      @work = ::Queue.new
    end

    def terminate(wait=false)
      @done = true
      @work << nil
      @thread.value if wait
    end

    def kill(wait=false)
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

    def request_process(work)
      raise ArgumentError, "Processor is shut down!" if @done
      raise ArgumentError, "Processor has not started!" unless @thread
      @work << work
    end

    private unless $TESTING

    def run
      begin
        while !@done
          job = @work.pop
          process(job) if job
        end
      rescue Exception => ex
        Sidekiq.logger.warn(ex.message)
        @mgr.processor_died(self, ex)
      end
    end

    def process(work)
      msgstr = work.message
      queue = work.queue_name

      ack = false
      begin
        msg = Sidekiq.load_json(msgstr)
        klass  = msg['class'.freeze].constantize
        worker = klass.new
        worker.jid = msg['jid'.freeze]

        stats(worker, msg, queue) do
          Sidekiq.server_middleware.invoke(worker, msg, queue) do
            # Only ack if we either attempted to start this job or
            # successfully completed it. This prevents us from
            # losing jobs if a middleware raises an exception before yielding
            ack = true
            execute_job(worker, cloned(msg['args'.freeze]))
          end
        end
        ack = true
      rescue Sidekiq::Shutdown
        # Had to force kill this job because it didn't finish
        # within the timeout.  Don't acknowledge the work since
        # we didn't properly finish it.
        ack = false
      rescue Exception => ex
        handle_exception(ex, msg || { :message => msgstr })
        raise
      ensure
        work.acknowledge if ack
      end

      @mgr.processor_done(self)
    end

    def execute_job(worker, cloned_args)
      worker.perform(*cloned_args)
    end

    def thread_identity
      @str ||= Thread.current.object_id.to_s(36)
    end

    def stats(worker, msg, queue)
      # Do not conflate errors from the job with errors caused by updating
      # stats so calling code can react appropriately
      retry_and_suppress_exceptions do
        hash = Sidekiq.dump_json({:queue => queue, :payload => msg, :run_at => Time.now.to_i })
        Sidekiq.redis do |conn|
          conn.pipelined do
            conn.hmset("#{identity}:workers", thread_identity, hash)
            conn.expire("#{identity}:workers", 14400)
          end
        end
      end

      nowdate = Time.now.utc.strftime("%Y-%m-%d".freeze)
      begin
        yield
      rescue Exception
        retry_and_suppress_exceptions do
          failed = "stat:failed:#{nowdate}"
          Sidekiq.redis do |conn|
            conn.pipelined do
              conn.incrby("stat:failed".freeze, 1)
              conn.incrby(failed, 1)
              conn.expire(failed, STATS_TIMEOUT)
            end
          end
        end
        raise
      ensure
        retry_and_suppress_exceptions do
          processed = "stat:processed:#{nowdate}"
          Sidekiq.redis do |conn|
            conn.pipelined do
              conn.hdel("#{identity}:workers", thread_identity)
              conn.incrby("stat:processed".freeze, 1)
              conn.incrby(processed, 1)
              conn.expire(processed, STATS_TIMEOUT)
            end
          end
        end
      end
    end

    # Deep clone the arguments passed to the worker so that if
    # the message fails, what is pushed back onto Redis hasn't
    # been mutated by the worker.
    def cloned(ary)
      Marshal.load(Marshal.dump(ary))
    end

    # If an exception occurs in the block passed to this method, that block will be retried up to max_retries times.
    # All exceptions will be swallowed and logged.
    def retry_and_suppress_exceptions(max_retries = 5)
      retry_count = 0
      begin
        yield
      rescue => e
        retry_count += 1
        if retry_count <= max_retries
          Sidekiq.logger.info {"Suppressing and retrying error: #{e.inspect}"}
          pause_for_recovery(retry_count)
          retry
        else
          handle_exception(e, { :message => "Exhausted #{max_retries} retries"})
        end
      end
    end

    def pause_for_recovery(retry_count)
      sleep(retry_count)
    end
  end
end
