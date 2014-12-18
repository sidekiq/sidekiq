require 'sidekiq/util'
require 'sidekiq/actor'

require 'sidekiq/middleware/server/retry_jobs'
require 'sidekiq/middleware/server/logging'

module Sidekiq
  ##
  # The Processor receives a message from the Manager and actually
  # processes it.  It instantiates the worker, runs the middleware
  # chain and then calls Sidekiq::Worker#perform.
  class Processor
    # To prevent a memory leak, ensure that stats expire. However, they should take up a minimal amount of storage
    # so keep them around for a long time
    STATS_TIMEOUT = 24 * 60 * 60 * 365 * 5

    include Util
    include Actor

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

    attr_accessor :proxy_id

    def initialize(boss)
      @boss = boss
    end

    def process(work)
      msgstr = work.message
      queue = work.queue_name

      @boss.async.real_thread(proxy_id, Thread.current)

      ack = true
      begin
        msg = Sidekiq.load_json(msgstr)
        klass  = msg['class'].constantize
        worker = klass.new
        worker.jid = msg['jid']

        stats(worker, msg, queue) do
          Sidekiq.server_middleware.invoke(worker, msg, queue) do
            execute_job(worker, cloned(msg['args']))
          end
        end
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

      @boss.async.processor_done(current_actor)
    end

    def inspect
      "<Processor##{object_id.to_s(16)}>"
    end

    def execute_job(worker, cloned_args)
      worker.perform(*cloned_args)
    end

    private

    def thread_identity
      @str ||= Thread.current.object_id.to_s(36)
    end

    def stats(worker, msg, queue)
      # Do not conflate errors from the job with errors caused by updating
      # stats so calling code can react appropriately
      retry_and_suppress_exceptions do
        hash = Sidekiq.dump_json({:queue => queue, :payload => msg, :run_at => Time.now.to_i })
        Sidekiq.redis do |conn|
          conn.multi do
            conn.hmset("#{identity}:workers", thread_identity, hash)
            conn.expire("#{identity}:workers", 60*60*4)
          end
        end
      end

      begin
        yield
      rescue Exception
        retry_and_suppress_exceptions do
          failed = "stat:failed:#{Time.now.utc.to_date}"
          Sidekiq.redis do |conn|
            conn.multi do
              conn.incrby("stat:failed", 1)
              conn.incrby(failed, 1)
              conn.expire(failed, STATS_TIMEOUT)
            end
          end
        end
        raise
      ensure
        retry_and_suppress_exceptions do
          processed = "stat:processed:#{Time.now.utc.to_date}"
          Sidekiq.redis do |conn|
            conn.multi do
              conn.hdel("#{identity}:workers", thread_identity)
              conn.incrby("stat:processed", 1)
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
    def retry_and_suppress_exceptions(max_retries = 2)
      retry_count = 0
      begin
        yield
      rescue => e
        retry_count += 1
        if retry_count <= max_retries
          Sidekiq.logger.debug {"Suppressing and retrying error: #{e.inspect}"}
          sleep(1)
          retry
        else
          handle_exception(e, { :message => "Exhausted #{max_retries} retries"})
        end
      end
    end
  end
end
