require 'celluloid'
require 'sidekiq/util'

require 'sidekiq/middleware/server/active_record'
require 'sidekiq/middleware/server/retry_jobs'
require 'sidekiq/middleware/server/logging'
require 'sidekiq/middleware/server/timeout'

module Sidekiq
  ##
  # The Processor receives a message from the Manager and actually
  # processes it.  It instantiates the worker, runs the middleware
  # chain and then calls Sidekiq::Worker#perform.
  class Processor
    include Util
    include Celluloid

#    exclusive :process

    def self.default_middleware
      Middleware::Chain.new do |m|
        m.add Middleware::Server::Logging
        m.add Middleware::Server::RetryJobs
        m.add Middleware::Server::ActiveRecord
        m.add Middleware::Server::Timeout
      end
    end

    def initialize(boss)
      @boss = boss
    end

    def process(msgstr, queue)
      defer do
        begin
          msg = Sidekiq.load_json(msgstr)
          klass  = constantize(msg['class'])
          worker = klass.new

          stats(worker, msg, queue) do
            Sidekiq.server_middleware.invoke(worker, msg, queue) do
              worker.perform(*cloned(msg['args']))
            end
          end
          rescue Exception => ex
            handle_exception(ex, msg || { :message => msgstr })
          raise
        end
      end
      @boss.processor_done!(current_actor)
    end

    # See http://github.com/tarcieri/celluloid/issues/22
    def inspect
      "#<Processor #{to_s}>"
    end

    def to_s
      @str ||= "#{hostname}:#{process_id}-#{Thread.current.object_id}:default"
    end

    private

    def stats(worker, msg, queue)
      redis do |conn|
        conn.multi do
          conn.sadd('workers', self)
          conn.setex("worker:#{self}:started", EXPIRY, Time.now.to_s)
          hash = {:queue => queue, :payload => msg, :run_at => Time.now.to_i }
          conn.setex("worker:#{self}", EXPIRY, Sidekiq.dump_json(hash))
        end
      end

      dying = false
      begin
        yield
      rescue Exception
        dying = true
        redis do |conn|
          conn.multi do
            conn.incrby("stat:failed", 1)
          end
        end
        raise
      ensure
        redis do |conn|
          conn.multi do
            conn.srem("workers", self)
            conn.del("worker:#{self}")
            conn.del("worker:#{self}:started")
            conn.incrby("stat:processed", 1)
          end
        end
      end
    end

    # Singleton classes are not clonable.
    SINGLETON_CLASSES = [ NilClass, TrueClass, FalseClass, Symbol, Fixnum, Float ].freeze

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
