# frozen_string_literal: true

require "sidekiq"

module Sidekiq
  class BasicFetch
    # We want the fetch operation to timeout every few seconds so the thread
    # can check if the process is shutting down.
    TIMEOUT = 2

    UnitOfWork = Struct.new(:queue, :job) {
      def acknowledge
        # nothing to do
      end

      def queue_name
        queue.delete_prefix("queue:")
      end

      def requeue
        Sidekiq.redis do |conn|
          conn.rpush(queue, job)
        end
      end
    }

    def initialize(options)
      raise ArgumentError, "missing queue list" unless options[:queues]
      @options = options
      @strictly_ordered_queues = !!@options[:strict]
      @queues = @options[:queues].map { |q| "queue:#{q}" }
      if @strictly_ordered_queues
        @queues.uniq!
        @queues << TIMEOUT
      end
    end

    def retrieve_work
      qs = queues_cmd
      # 4825 Sidekiq Pro with all queues paused will return an
      # empty set of queues with a trailing TIMEOUT value.
      if qs.size <= 1
        sleep(TIMEOUT)
        return nil
      end

      work = Sidekiq.redis { |conn| conn.brpop(*qs) }
      UnitOfWork.new(*work) if work
    end

    def bulk_requeue(inprogress, options)
      return if inprogress.empty?

      Sidekiq.logger.debug { "Re-queueing terminated jobs" }
      jobs_to_requeue = {}
      inprogress.each do |unit_of_work|
        jobs_to_requeue[unit_of_work.queue] ||= []
        jobs_to_requeue[unit_of_work.queue] << unit_of_work.job
      end

      Sidekiq.redis do |conn|
        conn.pipelined do
          jobs_to_requeue.each do |queue, jobs|
            conn.rpush(queue, jobs)
          end
        end
      end
      Sidekiq.logger.info("Pushed #{inprogress.size} jobs back to Redis")
    rescue => ex
      Sidekiq.logger.warn("Failed to requeue #{inprogress.size} jobs: #{ex.message}")
    end

    # Creating the Redis#brpop command takes into account any
    # configured queue weights. By default Redis#brpop returns
    # data from the first queue that has pending elements. We
    # recreate the queue command each time we invoke Redis#brpop
    # to honor weights and avoid queue starvation.
    def queues_cmd
      if @strictly_ordered_queues
        @queues
      else
        queues = @queues.shuffle!.uniq
        queues << TIMEOUT
        queues
      end
    end
  end
end
