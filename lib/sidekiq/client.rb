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
      raise(ArgumentError, "Message must be a Hash of the form: { 'class' => SomeWorker, 'args' => ['bob', 1, :foo => 'bar'] }") unless item.is_a?(Hash)
      raise(ArgumentError, "Message must include a class and set of arguments: #{item.inspect}") if !item['class'] || !item['args']
      raise(ArgumentError, "Message must include a Sidekiq::Worker class, not class name: #{item['class'].ancestors.inspect}") if !item['class'].is_a?(Class) || !item['class'].respond_to?('get_sidekiq_options')

      worker_class = item['class']
      item['class'] = item['class'].to_s

      item = worker_class.get_sidekiq_options.merge(item)
      item['retry'] = !!item['retry']
      queue = item['queue']
      item['jid'] = SecureRandom.base64

      pushed = false
      Sidekiq.client_middleware.invoke(worker_class, item, queue) do
        payload = Sidekiq.dump_json(item)
        Sidekiq.redis do |conn|
          if item['at']
            pushed = conn.zadd('schedule', item['at'].to_s, payload)
          else
            _, pushed = conn.multi do
              conn.sadd('queues', queue)
              conn.rpush("queue:#{queue}", payload)
            end
          end
        end
      end
      pushed ? item['jid'] : nil
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
  end
end
