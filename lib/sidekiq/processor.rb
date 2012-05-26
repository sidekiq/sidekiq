require 'celluloid'
require 'sidekiq/util'

require 'sidekiq/middleware/server/active_record'
require 'sidekiq/middleware/server/exception_handler'
require 'sidekiq/middleware/server/retry_jobs'
require 'sidekiq/middleware/server/logging'
require 'sidekiq/middleware/server/timeout'

module Sidekiq
  class Processor
    include Util
    include Celluloid

    def self.default_middleware
      Middleware::Chain.new do |m|
        m.add Middleware::Server::ExceptionHandler
        m.add Middleware::Server::Logging
        m.add Middleware::Server::RetryJobs
        m.add Middleware::Server::ActiveRecord
        m.add Middleware::Server::Timeout
      end
    end

    def initialize(boss)
      @boss = boss
    end

    def process(msg, queue)
      klass  = constantize(msg['class'])
      worker = klass.new
      defer do
        stats(worker, msg, queue) do
          Sidekiq.server_middleware.invoke(worker, msg, queue) do
            worker.perform(*msg['args'])
          end
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
          hash = {:queue => queue, :payload => msg, :run_at => Time.now.strftime("%Y/%m/%d %H:%M:%S %Z")}
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

    def hostname
      @h ||= `hostname`.strip
    end
  end
end
