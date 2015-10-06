require 'sidekiq'
require 'sidekiq/util'
require 'sidekiq/actor'
require 'thread'

module Sidekiq
  ##
  # The Fetcher blocks on Redis, waiting for a job to process
  # from the queues.  It gets the job and hands it to the Manager
  # to assign to a ready Processor.
  #
  #     f = Fetcher.new(mgr, opts)
  #     f.start
  #
  # Now anyone can call:
  #
  #     f.request_job
  #
  # and the fetcher will handle a job to the mgr.
  #
  # The Manager makes a request_job call for each idle processor
  # when Sidekiq starts and then issues a new request_job call
  # every time a Processor finishes a job.
  #
  class Fetcher
    include Util

    TIMEOUT = 1
    REQUEST = Object.new

    attr_reader :down

    def initialize(mgr, options)
      @done = false
      @down = nil
      @mgr = mgr
      @strategy = Fetcher.strategy.new(options)
      @requests = ConnectionPool::TimedStack.new
    end

    def request_job
      @requests << REQUEST
      nil
    end

    # Shut down this Fetcher instance, will pause until
    # the thread is dead.
    def terminate
      @done = true
      if @thread
        t = @thread
        @thread = nil
        @requests << 0
        t.value
      end
    end

    # Spins up the thread for this Fetcher instance
    def start
      @thread ||= safe_thread("fetcher") do
        while !@done
          get_one
        end
        Sidekiq.logger.info("Fetcher exiting...")
      end
    end

    # not for public use, testing only
    def wait_for_request
      begin
        req = nil
        begin
          req = @requests.pop(1)
          return if @done
        rescue Timeout::Error
          return
        end

        result = yield
        unless result
          @requests << req
        end
        result
      rescue => ex
        handle_fetch_exception(ex)
        @requests << REQUEST
      end
    end

    # not for public use, testing only
    def get_one
      wait_for_request do
        work = @strategy.retrieve_work
        ::Sidekiq.logger.info("Redis is online, #{Time.now - @down} sec downtime") if @down
        @down = nil

        @mgr.assign(work) if work
        work
      end
    end

    private

    def handle_fetch_exception(ex)
      if !@down
        logger.error("Error fetching message: #{ex}")
        ex.backtrace.each do |bt|
          logger.error(bt)
        end
      end
      @down ||= Time.now
      sleep(TIMEOUT)
    end

    def self.strategy
      Sidekiq.options[:fetch] || BasicFetch
    end
  end

  class BasicFetch
    def initialize(options)
      @strictly_ordered_queues = !!options[:strict]
      @queues = options[:queues].map { |q| "queue:#{q}" }
      @unique_queues = @queues.uniq
    end

    def retrieve_work
      work = Sidekiq.redis { |conn| conn.brpop(*queues_cmd) }
      UnitOfWork.new(*work) if work
    end

    # By leaving this as a class method, it can be pluggable and used by the Manager actor. Making it
    # an instance method will make it async to the Fetcher actor
    def self.bulk_requeue(inprogress, options)
      return if inprogress.empty?

      Sidekiq.logger.debug { "Re-queueing terminated jobs" }
      jobs_to_requeue = {}
      inprogress.each do |unit_of_work|
        jobs_to_requeue[unit_of_work.queue_name] ||= []
        jobs_to_requeue[unit_of_work.queue_name] << unit_of_work.message
      end

      Sidekiq.redis do |conn|
        conn.pipelined do
          jobs_to_requeue.each do |queue, jobs|
            conn.rpush("queue:#{queue}", jobs)
          end
        end
      end
      Sidekiq.logger.info("Pushed #{inprogress.size} messages back to Redis")
    rescue => ex
      Sidekiq.logger.warn("Failed to requeue #{inprogress.size} jobs: #{ex.message}")
    end

    UnitOfWork = Struct.new(:queue, :message) do
      def acknowledge
        # nothing to do
      end

      def queue_name
        queue.gsub(/.*queue:/, '')
      end

      def requeue
        Sidekiq.redis do |conn|
          conn.rpush("queue:#{queue_name}", message)
        end
      end
    end

    # Creating the Redis#brpop command takes into account any
    # configured queue weights. By default Redis#brpop returns
    # data from the first queue that has pending elements. We
    # recreate the queue command each time we invoke Redis#brpop
    # to honor weights and avoid queue starvation.
    def queues_cmd
      queues = @strictly_ordered_queues ? @unique_queues.dup : @queues.shuffle.uniq
      queues << Sidekiq::Fetcher::TIMEOUT
    end
  end
end
