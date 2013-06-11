require 'sidekiq/util'
require 'sidekiq/actor'

require 'sidekiq/middleware/server/active_record'
require 'sidekiq/middleware/server/retry_jobs'
require 'sidekiq/middleware/server/logging'

module Sidekiq
  ##
  # The Processor receives a message from the Manager and actually
  # processes it.  It instantiates the worker, runs the middleware
  # chain and then calls Sidekiq::Worker#perform.
  class Processor
    STATS_TIMEOUT = 180 * 24 * 60 * 60

    include Util
    include Actor

    def self.default_middleware
      Middleware::Chain.new do |m|
        m.add Middleware::Server::Logging
        m.add Middleware::Server::RetryJobs
        m.add Middleware::Server::ActiveRecord
      end
    end

    attr_accessor :proxy_id

    def initialize(boss)
      @boss = boss
    end

    def process(work)
      msgstr = work.message
      queue = work.queue_name

      do_defer do
        @boss.async.real_thread(proxy_id, Thread.current)

        begin
          msg = Sidekiq.load_json(msgstr)
          klass  = msg['class'].constantize
          worker = klass.new
          worker.jid = msg['jid']

          stats(worker, msg, queue) do
            Sidekiq.server_middleware.invoke(worker, msg, queue) do
              worker.perform(*cloned(msg['args']))
            end
          end
        rescue Sidekiq::Shutdown
          # Had to force kill this job because it didn't finish
          # within the timeout.
        rescue Exception => ex
          handle_exception(ex, msg || { :message => msgstr })
          raise
        ensure
          work.acknowledge
        end
      end

      @boss.async.processor_done(current_actor)
    end

    def inspect
      "<Processor##{object_id.to_s(16)}>"
    end

    private

    # We use Celluloid's defer to workaround tiny little
    # Fiber stacks (4kb!) in MRI 1.9.
    #
    # For some reason, Celluloid's thread dispatch, TaskThread,
    # is unstable under heavy concurrency but TaskFiber has proven
    # itself stable.
    NEED_DEFER = (RUBY_ENGINE == 'ruby' && RUBY_VERSION < '2.0.0')

    def do_defer(&block)
      if NEED_DEFER
        defer(&block)
      else
        yield
      end
    end

    def identity
      @str ||= "#{hostname}:#{process_id}-#{Thread.current.object_id}:default"
    end

    def stats(worker, msg, queue)
      redis do |conn|
        conn.multi do
          conn.sadd('workers', identity)
          conn.setex("worker:#{identity}:started", EXPIRY, Time.now.to_s)
          hash = {:queue => queue, :payload => msg, :run_at => Time.now.to_i }
          conn.setex("worker:#{identity}", EXPIRY, Sidekiq.dump_json(hash))
        end
      end

      begin
        yield
      rescue Exception
        redis do |conn|
          failed = "stat:failed:#{Time.now.utc.to_date}"
          result = conn.multi do
            conn.incrby("stat:failed", 1)
            conn.incrby(failed, 1)
          end
          conn.expire(failed, STATS_TIMEOUT) if result.last == 1
        end
        raise
      ensure
        redis do |conn|
          processed = "stat:processed:#{Time.now.utc.to_date}"
          result = conn.multi do
            conn.srem("workers", identity)
            conn.del("worker:#{identity}")
            conn.del("worker:#{identity}:started")
            conn.incrby("stat:processed", 1)
            conn.incrby(processed, 1)
          end
          conn.expire(processed, STATS_TIMEOUT) if result.last == 1
        end
      end
    end

    # Singleton classes are not clonable.
    SINGLETON_CLASSES = [ NilClass, TrueClass, FalseClass, Symbol, Fixnum, Float, Bignum ].freeze

    # Clone the arguments passed to the worker so that if
    # the message fails, what is pushed back onto Redis hasn't
    # been mutated by the worker.
    def cloned(ary)
      ary.map do |val|
        SINGLETON_CLASSES.include?(val.class) ? val : val.clone
      end
    end
  end
end
