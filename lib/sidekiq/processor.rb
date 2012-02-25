require 'celluloid'
require 'sidekiq/util'

require 'sidekiq/middleware/server/active_record'
require 'sidekiq/middleware/server/exception_handler'
require 'sidekiq/middleware/server/unique_jobs'
require 'sidekiq/middleware/server/failure_jobs'

module Sidekiq
  class Processor
    include Util
    include Celluloid

    def self.middleware
      raise "Sidekiq::Processor.middleware is now Sidekiq.server_middleware"
    end

    def self.default_middleware
      Middleware::Chain.new do |m|
        m.add Middleware::Server::ExceptionHandler
        m.add Middleware::Server::UniqueJobs
        m.add Middleware::Server::ActiveRecord
      end
    end

    attr_accessor :msg, :queue

    def initialize(boss)
      @boss = boss
      redis.sadd('workers', self)
    end

    def process(msg, queue)
      klass  = constantize(msg['class'])
      worker = klass.new
      stats(worker, msg, queue) do
        Sidekiq.server_middleware.invoke(worker, msg, queue) do
          worker.perform(*msg['args'])
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
      redis.with_connection do |conn|
        conn.multi do
          conn.set("worker:#{self}:started", Time.now.to_s)
          conn.set("worker:#{self}", MultiJson.encode(:queue => queue, :payload => msg,
                                                   :run_at => Time.now.strftime("%Y/%m/%d %H:%M:%S %Z")))
        end
      end

      dying = false
      begin
        yield
      rescue
        dying = true
        # Uh oh, error.  We will die so unregister as much as we can first.
        redis.with_connection do |conn|
          conn.multi do
            conn.incrby("stat:failed", 1)
            conn.del("stat:processed:#{self}")
            conn.srem("workers", self)
          end
        end
        raise
      ensure
        redis.with_connection do |conn|
          conn.multi do
            conn.del("worker:#{self}")
            conn.del("worker:#{self}:started")
            conn.incrby("stat:processed", 1)
            conn.incrby("stat:processed:#{self}", 1) unless dying
          end
        end
      end

    end

    def hostname
      @h ||= `hostname`.strip
    end
  end
end
