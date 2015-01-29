require 'sidekiq'
require 'sidekiq/util'
require 'sidekiq/actor'
require 'sidekiq/api'

module Sidekiq
  module Scheduled
    SETS = %w(retry schedule)

    class Enq
      def enqueue_jobs(now=Time.now.to_f.to_s, sorted_sets=SETS)
        # A job's "score" in Redis is the time at which it should be processed.
        # Just check Redis for the set of jobs with a timestamp before now.
        Sidekiq.redis do |conn|
          sorted_sets.each do |sorted_set|
            # Get the next item in the queue if it's score (time to execute) is <= now.
            # We need to go through the list one at a time to reduce the risk of something
            # going wrong between the time jobs are popped from the scheduled queue and when
            # they are pushed onto a work queue and losing the jobs.
            while job = conn.zrangebyscore(sorted_set, '-inf', now, :limit => [0, 1]).first do

              # Pop item off the queue and add it to the work queue. If the job can't be popped from
              # the queue, it's because another process already popped it so we can move on to the
              # next one.
              if conn.zrem(sorted_set, job)
                Sidekiq::Client.push(Sidekiq.load_json(job))
                Sidekiq::Logging.logger.debug { "enqueued #{sorted_set}: #{job}" }
              end
            end
          end
        end
      end
    end

    ##
    # The Poller checks Redis every N seconds for jobs in the retry or scheduled
    # set have passed their timestamp and should be enqueued.  If so, it
    # just pops the job back onto its original queue so the
    # workers can pick it up like any other job.
    class Poller
      include Util
      include Actor

      INITIAL_WAIT = 10

      def initialize
        @enq = (Sidekiq.options[:scheduled_enq] || Sidekiq::Scheduled::Enq).new
      end

      def poll(first_time=false)
        watchdog('scheduling poller thread died!') do
          initial_wait if first_time

          begin
            @enq.enqueue_jobs
          rescue => ex
            # Most likely a problem with redis networking.
            # Punt and try again at the next interval
            logger.error ex.message
            logger.error ex.backtrace.first
          end

          # Randomizing scales the interval by half since
          # on average calling `rand` returns 0.5.
          # We make up for this by doubling the interval
          after(poll_interval * 2 * rand) { poll }
        end
      end

      private

      # We do our best to tune poll_interval to the size of the active Sidekiq
      # cluster.  If you have 30 processes and poll every 15 seconds, that means one
      # Sidekiq is checking Redis every 0.5 seconds - way too often for most people
      # and really bad if the retry or scheduled sets are large.
      #
      # Instead try to avoid polling more than once every 15 seconds.  If you have
      # 30 Sidekiq processes, we'll set poll_interval to 30 * 15 * 2 or 900 seconds.
      # To keep things statistically random, we'll sleep a random amount between
      # 0 and 900 seconds for each poll or 450 seconds on average.  Otherwise restarting
      # all your Sidekiq processes at the same time will lead to them all polling at
      # the same time: the thundering herd problem.
      #
      # We only do this if poll_interval is unset (the default).
      def poll_interval
        Sidekiq.options[:poll_interval] ||= begin
          ps = Sidekiq::ProcessSet.new
          pcount = ps.size
          pcount = 1 if pcount == 0
          pcount * 15
        end
      end

      def initial_wait
        begin
          # Have all processes sleep between 5-15 seconds.  10 seconds
          # to give time for the heartbeat to register (if the poll interval is going to be calculated by the number
          # of workers), and 5 random seconds to ensure they don't all hit Redis at the same time.
          sleep(INITIAL_WAIT) unless Sidekiq.options[:poll_interval]
          sleep(5 * rand)
        rescue Celluloid::Task::TerminatedError
          # Hit Ctrl-C when Sidekiq is finished booting and we have a chance
          # to get here.
        end
      end

    end
  end
end
