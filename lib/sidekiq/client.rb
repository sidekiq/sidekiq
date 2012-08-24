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
      push_to_queue(item, false)
    end

    ##
    # Sibling of the push method, push_batch implies multiple jobs should be pushed, in batch, to Redis. This method
    # skips all client-side middleware.
    #
    #   queue - the named queue to use, default 'default'
    #   class - the worker class to call, required
    #   args - an array of arrays of simple arguments to the perform method.  The arrays within the base array must be JSON serializable
    #   retry - whether to retry this job if it fails, true or false, default true
    #   backtrace - whether to save any error backtrace, default false
    #
    # All options must be strings, not symbols.  NB: because we are serializing to JSON, all
    # symbols in 'args' will be converted to strings.
    #
    # Returns nil if not pushed to Redis or an array of unique Job IDs if pushed.
    #
    # Example:
    #   Sidekiq::Client.push_batch('queue' => 'my_queue', 'class' => MyWorker, 'args' => [['bar', 2, :bat => 'foo'], ['foo', 1, :bat => 'bar']])
    #
    def self.push_batch(item)
      #TODO: Actually support scheduled batches
      raise(ArgumentError, "Batches cannot be scheduled at this time.") if item['at']
      self.push_to_queue(item, true)
    end

    # Redis compatibility helper.  Example usage:
    #
    #   Sidekiq::Client.enqueue(MyWorker, 'foo', 1, :bat => 'bar')
    #
    # Messages are enqueued to the 'default' queue.
    #
    def self.enqueue(klass, *args)
      klass.perform_async(*args)
    end

    private

    def self.normalize_item(item)
      raise(ArgumentError, "Message must be a Hash of the form: { 'class' => SomeWorker, 'args' => ['bob', 1, :foo => 'bar'] }") unless item.is_a?(Hash)
      raise(ArgumentError, "Message must include a class and set of arguments: #{item.inspect}") if !item['class'] || !item['args']
      raise(ArgumentError, "Message must include a Sidekiq::Worker class, not class name: #{item['class'].ancestors.inspect}") if !item['class'].is_a?(Class) || !item['class'].respond_to?('get_sidekiq_options')

      normalized_item = item.dup

      normalized_item['class'] = normalized_item['class'].to_s
      normalized_item['retry'] = !!normalized_item['retry']
      normalized_item['jid'] = SecureRandom.base64

      item['class'].get_sidekiq_options.merge normalized_item
    end

    def self.prepare_payload(item, batch)
      base_message = item.dup

      args = batch ? base_message['args'] : [base_message['args']]
      payload = args.collect do |arguments|
        jid = batch ? SecureRandom.base64 : item['jid']
        Sidekiq.dump_json base_message.merge({'args' => arguments, 'jid' => jid})
      end

      batch ? payload : payload.first
    end

    #Push the message to redis
    def self.push_to_queue(item, batch)
      normalized_item = normalize_item item
      payload = prepare_payload normalized_item, batch

      pushed = false

      if batch
        pushed = perform_push normalized_item['queue'], payload
      else
        Sidekiq.client_middleware.invoke(item['class'], normalized_item, normalized_item['queue']) do
          pushed = perform_push normalized_item['queue'], payload, normalized_item['at']
        end
      end

      return nil unless pushed
      batch ? payload.collect {|job| Sidekiq.load_json(job)['jid']} : normalized_item['jid']
    end

    def self.perform_push(queue, payload, at = nil)
      pushed = false

      Sidekiq.redis do |conn|
        if at
          pushed = conn.zadd('schedule', at.to_s, payload)
        else
          _, pushed = conn.multi do
            conn.sadd('queues', queue)
            conn.rpush("queue:#{queue}", payload)
          end
        end
      end

      pushed
    end
  end
end
