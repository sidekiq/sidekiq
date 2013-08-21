require 'sidekiq'
require 'sidekiq/util'
require 'sidekiq/actor'
require 'sidekiq/cron'

module Sidekiq
  module Cron

    POLL_INTERVAL = 5

    ##
    # The Poller checks Redis every N seconds for sheduled cron jobs
    class Poller
      include Util
      include Actor

      SETS = %w(cron_jobs)

      def poll(first_time=false)
        watchdog('scheduling poller thread died!') do
          add_jitter if first_time

          begin
            # A message's "score" in Redis is the time at which it should be processed.
            # Just check Redis for the set of messages with a timestamp before now.
            time_now = Time.now
            now = time_now.to_f.to_s

            Sidekiq.redis do |conn|
              SETS.each do |set|
                # Get the next item in the queue if it's score (time to execute) is <= now.
                # We need to go through the list one at a time to reduce the risk of something
                # going wrong between the time jobs are popped from the scheduled queue and when
                # they are pushed onto a work queue and losing the jobs.
                conn.smembers(set).each do |cron_job_key|

                  #get cron setting from cron_job
                  cron = conn.hget(cron_job_key, "cron")

                  #get last_run_time from cron_job
                  last_run_time = Time.parse(conn.hget(cron_job_key, "last_run_time"))

                  #when it was last time to run
                  should_run_time = Cron::Scheduler.get_last_time(cron, time_now)

                  # if should_run_time is younger than last_run_time &
                  # should_run_time was added for first time to run list
                  if (
                    last_run_time < should_run_time &&
                    conn.zadd("#{cron_job_key}:run", now, should_run_time)
                  )

                    # remove previous informations about run times 
                    # this will clear redis and make sure that redis will
                    # not overflow with memory
                    conn.zremrangebyscore("#{cron_job_key}:run", 0, "(#{now}")
                      
                    #set last time of runned job
                    conn.hset cron_job_key, "last_run_time", should_run_time.to_s

                    #get all data from cron job
                    message = conn.hget(cron_job_key, "message")
                                        
                    Sidekiq::Client.push(Sidekiq.load_json(message))
                    logger.debug { "enqueued #{cron_job_key.split(":", 2).last}: #{message}" }
                  end
                end
              end
            end
          rescue => ex
            # Most likely a problem with redis networking.
            # Punt and try again at the next interval
            logger.error ex.message
            logger.error ex.backtrace.first
          end

          after(poll_interval) { poll }
        end
      end

      private

      def poll_interval
        Sidekiq.options[:poll_interval] || POLL_INTERVAL
      end

      def add_jitter
        begin
          sleep(poll_interval * rand)
        rescue Celluloid::Task::TerminatedError
          # Hit Ctrl-C when Sidekiq is finished booting and we have a chance
          # to get here.
        end
      end

    end
  end
end
