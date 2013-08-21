require 'sidekiq'
require 'sidekiq/util'
require 'sidekiq/actor'
require 'parse-cron'

module Sidekiq
  module Cron

    module Scheduler
      extend Util

      # load cron jobs from Hash
      # input structure should look like:
      # {
      #   'name_of_job' => {
      #     'class' => 'MyClass',
      #     'cron'  => '1 * * * *',
      #     'args'  => '(OPTIONAL) [Array or Hash]'
      #   },
      #   'My super iber cool job' => {
      #     'class' => 'SecondClass',
      #     'cron'  => '*/5 * * * *'
      #   }
      # }
      #
      def self.load_jobs_from_hash hash
        load_jobs_from_hash hash.inject([]) do |out,(key, job)|
          job['name'] = key
          out << job
        end
      end


      # load cron jobs from Array
      # input structure should look like:
      # [
      #   {
      #     'name'  => 'name_of_job',
      #     'class' => 'MyClass',
      #     'cron'  => '1 * * * *',
      #     'args'  => '(OPTIONAL) [Array or Hash]'
      #   },
      #   {
      #     'name'  => 'Cool Job for Second Class',
      #     'class' => 'SecondClass',
      #     'cron'  => '*/5 * * * *'
      #   }
      # ]
      #
      def self.load_jobs_from_hash array
        array.each do |job|
          add_job(job)
        end
      end

      # add job to cron jobs
      # input:
      #   name: (string) - name of job
      #   cron: (string: '* * * * *' - cron specification when to run job
      #   class: (string|class) - which class to perform
      # optional input:
      #   queue: (string) - which queue to use for enquing (will override class queue)
      #   args: (array|hash|nil) - arguments for permorm method

      def self.add_job job

        last_time = get_last_time(job['cron'])

        #build data for cron
        job_bag = {
          'name'  => job['name'].to_s, 
          'cron'  => job['cron'],
          'last_run_time' => last_time.to_s,
        }

        message = {
          "class" => job['class'],
          "args"  => job["args"].is_a?(Array) ? job["args"] : [job["args"]],
        }
        #get right data for message
        job_bag["message"] = case job['class']
          when Class
            job['class'].get_sidekiq_options.merge(message)
          when String
            job['class'].constantize.get_sidekiq_options.merge(message)
        end

        #override queue if setted in config
        job_bag['message']['queue'] = job['queue'] if job['queue']

        #Dump message to JSON
        job_bag["message"] = Sidekiq.dump_json(job_bag["message"])

        Sidekiq.redis do |conn|
          key = cron_job_key(job['name'])

          #add to set of all jobs
          conn.sadd  cron_jobs_key, key

          #add informations for this job!
          conn.hmset key, *hash_to_redis(job_bag)

          #add information about last time! - don't enque right after scheduler poller starts!
          conn.zadd(cron_job_runs_key(job['name']), Time.now.to_i, last_time.to_s)
        end
      end

      # get all cron jobs
      def self.all_jobs
        out = []
        Sidekiq.redis do |conn|
          out = conn.smembers(cron_jobs_key).collect do |key|
            conn.hgetall(key)
          end
        end
        out
      end

      # remove job from cron jobs by name
      # input:
      #   first arg: name (string) - name of job (must be same - case sensitive)
      def self.remove_job name
        Sidekiq.redis do |conn|
          key = cron_job_key(name)

          #delete from set
          conn.srem cron_jobs_key, key
          
          #delete runned timestamps
          conn.del cron_job_runs_key(name)

          #delete main job
          conn.del key
        end
      end

      # remove all job from cron
      def self.remove_all_jobs!
        Sidekiq.redis do |conn|
          conn.smembers(cron_jobs_key).each do |key|
            #delete job data
            conn.del key 

            #delete job runs
            conn.del cron_job_runs_from_key(key)
          end

          #delete set of jobs!
          conn.del cron_jobs_key
        end
        logger.info { "Cron Jobs - deleted all jobs" }
      end

      #enque cron job to queue by name of job
      def self.enque_job_by_name name
        enque_job_by_key cron_job_key(name)
      end

      #enque cron job to queue by redis key of job
      def self.enque_job_by_key key
        Sidekiq.redis do |conn|
          #get all data from cron job
          message = conn.hget(key, "message")

          Sidekiq::Client.push(Sidekiq.load_json(message))

          #set last time of runned job
          conn.hset key, "last_run_time", Time.now.to_s

          logger.debug { "enqueued #{key} directly by key call: #{message}" }
        end
      end

      # Parse cron specification '* * * * *' and returns
      # time when last run should be performed
      def self.get_last_time cron, now = Time.now
        # add 1 minute to Time now - Cron parser return last time after minute ends,
        # so by adding 60 second we will get last time after the right time happens 
        # without any delay!
        CronParser.new(cron).last(now + 60)
      end


      private

      # Redis key for set of all cron jobs
      def self.cron_jobs_key
        "cron_jobs"
      end

      # Redis key for storing one cron job
      def self.cron_job_key name
        "cron_job:#{name}"
      end

      # Redis key for storing one cron job run times
      # (when poller added job to queue)
      def self.cron_job_runs_key name
        "cron_job:#{name}:run"
      end

      # Redis key for storing one cron job run times
      # (when poller added job to queue)
      def self.cron_job_runs_from_key key
        "#{key}:run"
      end
        
      # Give Hash
      # returns array for using it for redis.hmset
      def self.hash_to_redis hash
        hash.inject([]){ |arr,kv| arr + [kv[0], kv[1]] }
      end

    end
  end
end
