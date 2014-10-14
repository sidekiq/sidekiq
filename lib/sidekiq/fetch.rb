require 'sidekiq'
require 'sidekiq/util'
require 'sidekiq/actor'

module Sidekiq
  ##
  # The Fetcher blocks on Redis, waiting for a message to process
  # from the queues.  It gets the message and hands it to the Manager
  # to assign to a ready Processor.
  class Fetcher
    include Util
    include Actor

    TIMEOUT = 1

    attr_reader :down

    def initialize(mgr, options)
      @down = nil
      @mgr = mgr
      @strategy = Fetcher.strategy.new(options)
    end

    # Fetching is straightforward: the Manager makes a fetch
    # request for each idle processor when Sidekiq starts and
    # then issues a new fetch request every time a Processor
    # finishes a message.
    #
    # Because we have to shut down cleanly, we can't block
    # forever and we can't loop forever.  Instead we reschedule
    # a new fetch if the current fetch turned up nothing.
    def fetch
      watchdog('Fetcher#fetch died') do
        return if Sidekiq::Fetcher.done?

        begin
          work = @strategy.retrieve_work
          ::Sidekiq.logger.info("Redis is online, #{Time.now.to_f - @down.to_f} sec downtime") if @down
          @down = nil

          if work
            @mgr.async.assign(work)
          else
            after(0) { fetch }
          end
        rescue => ex
          handle_fetch_exception(ex)
        end

      end
    end

    private

    def pause
      sleep(TIMEOUT)
    end

    def handle_fetch_exception(ex)
      if !@down
        logger.error("Error fetching message: #{ex}")
        ex.backtrace.each do |bt|
          logger.error(bt)
        end
      end
      @down ||= Time.now
      pause
      after(0) { fetch }
    rescue Task::TerminatedError
      # If redis is down when we try to shut down, all the fetch backlog
      # raises these errors.  Haven't been able to figure out what I'm doing wrong.
    end

    # Ugh.  Say hello to a bloody hack.
    # Can't find a clean way to get the fetcher to just stop processing
    # its mailbox when shutdown starts.
    def self.done!
      @done = true
    end

    def self.reset # testing only
      @done = nil
    end

    def self.done?
      @done
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
      work = nil

      Sidekiq.redis do |conn|
        queues.find do |queue|
          response = conn.multi do
            conn.zrange(queue, 0, 0)
            conn.zremrangebyrank(queue, 0, 0)
          end.flatten(1)

          next if response.length == 1
          work = [queue, response.first]
          break
        end
      end

      return UnitOfWork.new(*work) if work
      sleep 1; nil
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
            jobs.each do |job|
              conn.zadd("queue:#{queue}", 0, job)
            end
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
          conn.zadd("queue:#{queue_name}", 0, message)
        end
      end
    end

    def queues
      @strictly_ordered_queues ? @unique_queues.dup : @queues.shuffle.uniq
    end
  end
end
