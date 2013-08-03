require 'securerandom'

require 'sidekiq/middleware/chain'

module Sidekiq
  class Client
    class << self

      def default_middleware
        Middleware::Chain.new do
        end
      end

      def registered_workers
        Sidekiq.redis { |x| x.smembers('workers') }
      end

      def registered_queues
        Sidekiq.redis { |x| x.smembers('queues') }
      end

      ##
      # The main method used to push a job to Redis.  Accepts a number of options:
      #
      #   queue - the named queue to use, default 'default'
      #   class - the worker class to call, required
      #   args - an array of simple arguments to the perform method, must be JSON-serializable
      #   retry - whether to retry this job if it fails, true or false, default true
      #   backtrace - whether to save any error backtrace, default false
      #
      # All options must be strings, not symbols.  NB: because we are serializing to JSON, all
      # symbols in 'args' will be converted to strings.
      #
      # Returns nil if not pushed to Redis or a unique Job ID if pushed.
      #
      # Example:
      #   Sidekiq::Client.push('queue' => 'my_queue', 'class' => MyWorker, 'args' => ['foo', 1, :bat => 'bar'])
      #
      def push(item)
        normed = normalize_item(item)

        Sidekiq.client_middleware.invoke(item['class'], normed, normed['queue']) do |worker_class, payload, queue|
          raw_push([payload]) ? payload['jid'] : nil
        end
      end

      ##
      # Push a large number of jobs to Redis.  In practice this method is only
      # useful if you are pushing tens of thousands of jobs or more.  This method
      # basically cuts down on the redis round trip latency.
      #
      # Takes the same arguments as Client.push except that args is expected to be
      # an Array of Arrays.  All other keys are duplicated for each job.  Each job
      # is run through the client middleware pipeline and each job gets its own Job ID
      # as normal.
      #
      # Returns the number of jobs pushed or nil if the pushed failed.  The number of jobs
      # pushed can be less than the number given if the middleware stopped processing for one
      # or more jobs.
      def push_bulk(items)
        normed = normalize_item(items, true)
        args_array = normed.map {|item| [items['class'], item, item['queue']]}

        # Bulk run!
        Sidekiq.client_middleware.invoke_bulk(*args_array) do |*args_array|
          payloads = args_array.map {|args| args[1]}

          if not payloads.empty?
            raw_push(payloads) ? payloads.size : nil
          end
        end
      end

      # Resque compatibility helpers.
      #
      # Example usage:
      #   Sidekiq::Client.enqueue(MyWorker, 'foo', 1, :bat => 'bar')
      #
      # Messages are enqueued to the 'default' queue.
      #
      def enqueue(klass, *args)
        klass.client_push('class' => klass, 'args' => args)
      end

      # Example usage:
      #   Sidekiq::Client.enqueue_to(:queue_name, MyWorker, 'foo', 1, :bat => 'bar')
      #
      def enqueue_to(queue, klass, *args)
        klass.client_push('queue' => queue, 'class' => klass, 'args' => args)
      end

      private

      def raw_push(payloads)
        pushed = false
        Sidekiq.redis do |conn|
          if payloads.first['at']
            pushed = conn.zadd('schedule', payloads.map do |hash|
              at = hash.delete('at').to_s
              [at, Sidekiq.dump_json(hash)]
            end)
          else
            q = payloads.first['queue']
            to_push = payloads.map { |entry| Sidekiq.dump_json(entry) }
            _, pushed = conn.multi do
              conn.sadd('queues', q)
              conn.lpush("queue:#{q}", to_push)
            end
          end
        end
        pushed
      end

      def set_job_attrs(item)
        item['jid'] ||= SecureRandom.hex(12)
        item['enqueued_at'] = Time.now.to_f
        item
      end

      def normalize_item(item, bulk=false)
        raise(ArgumentError, "Message must be a Hash of the form: { 'class' => SomeWorker, 'args' => ['bob', 1, :foo => 'bar'] }") unless item.is_a?(Hash)
        raise(ArgumentError, "Message must include a class and set of arguments: #{item.inspect}") if !item['class'] || !item['args']
        raise(ArgumentError, "Message args must be an Array") unless item['args'].is_a?(Array)
        raise(ArgumentError, "Message class must be either a Class or String representation of the class name") unless item['class'].is_a?(Class) || item['class'].is_a?(String)

        if item['class'].is_a?(Class)
          raise(ArgumentError, "Message must include a Sidekiq::Worker class, not class name: #{item['class'].ancestors.inspect}") if !item['class'].respond_to?('get_sidekiq_options')
          normalized_item = item['class'].get_sidekiq_options.merge(item)
          normalized_item['class'] = normalized_item['class'].to_s
        else
          normalized_item = Sidekiq::Worker::ClassMethods::DEFAULT_OPTIONS.merge(item)
        end

        if not bulk
          set_job_attrs(normalized_item)
        else
          normalized_item['args'].map do |args|
            raise ArgumentError, "Bulk arguments must be an Array of Arrays: [[1], [2]]" if !args.is_a?(Array)

            set_job_attrs(normalized_item.merge('args' => args))
          end
        end
      end

    end
  end
end
