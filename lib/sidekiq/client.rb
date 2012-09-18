require 'securerandom'

require 'sidekiq/middleware/chain'

module Sidekiq
  class Client

    def self.default_middleware
      Middleware::Chain.new do |m|
      end
    end

    def self.registered_workers
      Sidekiq.redis { |x| x.smembers('workers') }
    end

    def self.registered_queues
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
    def self.push(item)
      normed = normalize_item(item)
      normed, payload = process_single(item['class'], normed)

      pushed = false
      Sidekiq.redis do |conn|
        if normed['at']
          pushed = conn.zadd('schedule', normed['at'].to_s, payload)
        else
          _, pushed = conn.multi do
            conn.sadd('queues', normed['queue'])
            conn.rpush("queue:#{normed['queue']}", payload)
          end
        end
      end if normed
      pushed ? normed['jid'] : nil
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
    def self.push_bulk(items)
      normed = normalize_item(items)
      payloads = items['args'].map do |args|
        _, payload = process_single(items['class'], normed.merge('args' => args, 'jid' => SecureRandom.hex(12)))
        payload
      end.compact

      pushed = false
      Sidekiq.redis do |conn|
        _, pushed = conn.multi do
          conn.sadd('queues', normed['queue'])
          conn.rpush("queue:#{normed['queue']}", payloads)
        end
      end

      pushed ? payloads.size : nil
    end

    # Resque compatibility helpers.
    #
    # Example usage:
    #   Sidekiq::Client.enqueue(MyWorker, 'foo', 1, :bat => 'bar')
    #
    # Messages are enqueued to the 'default' queue.
    #
    def self.enqueue(klass, *args)
      klass.client_push('class' => klass, 'args' => args)
    end

    # Example usage:
    #   Sidekiq::Client.enqueue_to(:queue_name, MyWorker, 'foo', 1, :bat => 'bar')
    #
    def self.enqueue_to(queue, klass, *args)
      klass.client_push('queue' => queue, 'class' => klass, 'args' => args)
    end

    private

    def self.process_single(worker_class, item)
      queue = item['queue']

      Sidekiq.client_middleware.invoke(worker_class, item, queue) do
        payload = Sidekiq.dump_json(item)
        return item, payload
      end
    end

    def self.normalize_item(item)
      raise(ArgumentError, "Message must be a Hash of the form: { 'class' => SomeWorker, 'args' => ['bob', 1, :foo => 'bar'] }") unless item.is_a?(Hash)
      raise(ArgumentError, "Message must include a class and set of arguments: #{item.inspect}") if !item['class'] || !item['args']
      raise(ArgumentError, "Message must include a Sidekiq::Worker class, not class name: #{item['class'].ancestors.inspect}") if !item['class'].is_a?(Class) || !item['class'].respond_to?('get_sidekiq_options')

      normalized_item = item['class'].get_sidekiq_options.merge(item.dup)
      normalized_item['class'] = normalized_item['class'].to_s
      normalized_item['retry'] = !!normalized_item['retry']
      normalized_item['jid'] = SecureRandom.hex(12)

      normalized_item
    end

  end
end
