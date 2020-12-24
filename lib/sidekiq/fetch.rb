# frozen_string_literal: true

require "sidekiq"

module Sidekiq
  class BasicFetch
    include Loggable

    # We want the fetch operation to timeout every few seconds so the thread
    # can check if the process is shutting down.
    TIMEOUT = 2

    UnitOfWork = Struct.new(:queue, :job) {
      def queue_name
        queue.delete_prefix("queue:")
      end
    }

    def initialize(cfg)
      raise ArgumentError, "missing queue list" unless cfg.queues

      qs = cfg.queues
      cfg.register_component(self)
      @strict = qs.size == qs.uniq.size
      @timeout = { timeout: TIMEOUT }
      @queues = qs.map { |q| "queue:#{q}" }
    end

    def finalize(cfg)
      @pool = cfg.pool
      @logger = cfg.logger
    end

    def acknowledge(uow)
      # nothing to do
    end

    def requeue(uow)
      @pool.with do |conn|
        conn.rpush(uow.queue, uow.job)
      end
    end

    def retrieve_work
      work = @pool.with { |conn| conn.brpop(*queues_cmd, @timeout) }
      UnitOfWork.new(*work) if work
    end

    def bulk_requeue(inprogress)
      return if inprogress.empty?

      debug { "Re-queueing terminated jobs" }
      jobs_to_requeue = {}
      inprogress.each do |unit_of_work|
        jobs_to_requeue[unit_of_work.queue] ||= []
        jobs_to_requeue[unit_of_work.queue] << unit_of_work.job
      end

      @pool.with do |conn|
        conn.pipelined do
          jobs_to_requeue.each do |queue, jobs|
            conn.rpush(queue, jobs)
          end
        end
      end
      info("Pushed #{inprogress.size} jobs back to Redis")
    rescue => ex
      warn("Failed to requeue #{inprogress.size} jobs: #{ex.message}")
    end

    # Creating the Redis#brpop command takes into account any
    # configured queue weights. By default Redis#brpop returns
    # data from the first queue that has pending elements. We
    # recreate the queue command each time we invoke Redis#brpop
    # to honor weights and avoid queue starvation.
    def queues_cmd
      if @strict
        @queues
      else
        @queues.shuffle!.uniq
      end
    end
  end
end
