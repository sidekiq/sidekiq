# frozen_string_literal: true

require "sidekiq"
require "sidekiq/util"
require "sidekiq/api"

module Sidekiq
  module Scheduled
    SETS = %w[retry schedule]

    class Enq
      LUA_ZPOPBYSCORE = <<~LUA
        local key, now = KEYS[1], ARGV[1]
        local jobs = redis.call("zrangebyscore", key, "-inf", now, "limit", 0, 1)
        if jobs[1] then
          redis.call("zrem", key, jobs[1])
          return jobs[1]
        end
      LUA

      def initialize
        @done = false
        @lua_zpopbyscore_sha = nil
      end

      def enqueue_jobs(sorted_sets = SETS)
        # A job's "score" in Redis is the time at which it should be processed.
        # Just check Redis for the set of jobs with a timestamp before now.
        Sidekiq.redis do |conn|
          sorted_sets.each do |sorted_set|
            # Get next item in the queue with score (time to execute) <= now.
            # We need to go through the list one at a time to reduce the risk of something
            # going wrong between the time jobs are popped from the scheduled queue and when
            # they are pushed onto a work queue and losing the jobs.
            while !@done && (job = zpopbyscore(conn, keys: [sorted_set], argv: [Time.now.to_f.to_s]))
              Sidekiq::Client.push(Sidekiq.load_json(job))
              Sidekiq.logger.debug { "enqueued #{sorted_set}: #{job}" }
            end
          end
        end
      end

      def terminate
        @done = true
      end

      private

      def zpopbyscore(conn, keys: nil, argv: nil)
        if @lua_zpopbyscore_sha.nil?
          raw_conn = conn.respond_to?(:redis) ? conn.redis : conn
          @lua_zpopbyscore_sha = raw_conn.script(:load, LUA_ZPOPBYSCORE)
        end

        conn.evalsha(@lua_zpopbyscore_sha, keys, argv)
      rescue RedisConnection.adapter::CommandError => e
        raise unless e.message.start_with?("NOSCRIPT")

        @lua_zpopbyscore_sha = nil
        retry
      end
    end

    ##
    # The Poller checks Redis every N seconds for jobs in the retry or scheduled
    # set have passed their timestamp and should be enqueued.  If so, it
    # just pops the job back onto its original queue so the
    # workers can pick it up like any other job.
    class Poller
      include Util

      INITIAL_WAIT = 10

      def initialize
        @enq = (Sidekiq.options[:scheduled_enq] || Sidekiq::Scheduled::Enq).new
        @sleeper = ConnectionPool::TimedStack.new
        @done = false
        @thread = nil
        @count_calls = 0
      end

      # Shut down this instance, will pause until the thread is dead.
      def terminate
        @done = true
        @enq.terminate if @enq.respond_to?(:terminate)

        if @thread
          t = @thread
          @thread = nil
          @sleeper << 0
          t.value
        end
      end

      def start
        @thread ||= safe_thread("scheduler") {
          initial_wait

          until @done
            enqueue
            wait
          end
          Sidekiq.logger.info("Scheduler exiting...")
        }
      end

      def enqueue
        @enq.enqueue_jobs
      rescue => ex
        # Most likely a problem with redis networking.
        # Punt and try again at the next interval
        logger.error ex.message
        handle_exception(ex)
      end

      private

      def wait
        @sleeper.pop(random_poll_interval)
      rescue Timeout::Error
        # expected
      rescue => ex
        # if poll_interval_average hasn't been calculated yet, we can
        # raise an error trying to reach Redis.
        logger.error ex.message
        handle_exception(ex)
        sleep 5
      end

      def random_poll_interval
        # We want one Sidekiq process to schedule jobs every N seconds.  We have M processes
        # and **don't** want to coordinate.
        #
        # So in N*M second timespan, we want each process to schedule once.  The basic loop is:
        #
        # * sleep a random amount within that N*M timespan
        # * wake up and schedule
        #
        # We want to avoid one edge case: imagine a set of 2 processes, scheduling every 5 seconds,
        # so N*M = 10.  Each process decides to randomly sleep 8 seconds, now we've failed to meet
        # that 5 second average. Thankfully each schedule cycle will sleep randomly so the next
        # iteration could see each process sleep for 1 second, undercutting our average.
        #
        # So below 10 processes, we special case and ensure the processes sleep closer to the average.
        # In the example above, each process should schedule every 10 seconds on average. We special
        # case smaller clusters to add 50% so they would sleep somewhere between 5 and 15 seconds.
        # As we run more processes, the scheduling interval average will approach an even spread
        # between 0 and poll interval so we don't need this artifical boost.
        #
        if process_count < 10
          # For small clusters, calculate a random interval that is ±50% the desired average.
          poll_interval_average * rand + poll_interval_average.to_f / 2
        else
          # With 10+ processes, we should have enough randomness to get decent polling
          # across the entire timespan
          poll_interval_average * rand
        end
      end

      # We do our best to tune the poll interval to the size of the active Sidekiq
      # cluster.  If you have 30 processes and poll every 15 seconds, that means one
      # Sidekiq is checking Redis every 0.5 seconds - way too often for most people
      # and really bad if the retry or scheduled sets are large.
      #
      # Instead try to avoid polling more than once every 15 seconds.  If you have
      # 30 Sidekiq processes, we'll poll every 30 * 15 or 450 seconds.
      # To keep things statistically random, we'll sleep a random amount between
      # 225 and 675 seconds for each poll or 450 seconds on average.  Otherwise restarting
      # all your Sidekiq processes at the same time will lead to them all polling at
      # the same time: the thundering herd problem.
      #
      # We only do this if poll_interval_average is unset (the default).
      def poll_interval_average
        Sidekiq.options[:poll_interval_average] ||= scaled_poll_interval
      end

      # Calculates an average poll interval based on the number of known Sidekiq processes.
      # This minimizes a single point of failure by dispersing check-ins but without taxing
      # Redis if you run many Sidekiq processes.
      def scaled_poll_interval
        process_count * Sidekiq.options[:average_scheduled_poll_interval]
      end

      def process_count
        # The work buried within Sidekiq::ProcessSet#cleanup can be
        # expensive at scale. Cut it down by 90% with this counter.
        # NB: This method is only called by the scheduler thread so we
        # don't need to worry about the thread safety of +=.
        pcount = Sidekiq::ProcessSet.new(@count_calls % 10 == 0).size
        pcount = 1 if pcount == 0
        @count_calls += 1
        pcount
      end

      def initial_wait
        # Have all processes sleep between 5-15 seconds.  10 seconds
        # to give time for the heartbeat to register (if the poll interval is going to be calculated by the number
        # of workers), and 5 random seconds to ensure they don't all hit Redis at the same time.
        total = 0
        total += INITIAL_WAIT unless Sidekiq.options[:poll_interval_average]
        total += (5 * rand)

        @sleeper.pop(total)
      rescue Timeout::Error
      end
    end
  end
end
