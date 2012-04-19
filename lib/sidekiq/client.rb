require 'multi_json'

require 'sidekiq/middleware/chain'
require 'sidekiq/middleware/client/unique_jobs'

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

    # DEPRECATED
    def self.queue_mappings
      @queue_mappings ||= {}
    end

    # Example usage:
    # Sidekiq::Client.push('queue' => 'my_queue', 'class' => MyWorker, 'args' => ['foo', 1, :bat => 'bar'])
    def self.push(item)
      raise(ArgumentError, "Message must be a Hash of the form: { 'class' => SomeWorker, 'args' => ['bob', 1, :foo => 'bar'] }") unless item.is_a?(Hash)
      raise(ArgumentError, "Message must include a class and set of arguments: #{item.inspect}") if !item['class'] || !item['args']
      raise(ArgumentError, "Message must include a Sidekiq::Worker class, not class name: #{item['class'].ancestors.inspect}") if !item['class'].is_a?(Class) || !item['class'].respond_to?('get_sidekiq_options')

      item['retry'] = !!item['class'].get_sidekiq_options['retry']
      queue = item['queue'] || item['class'].get_sidekiq_options['queue'] || queue_mappings[item['class'].to_s] || 'default'
      worker_class = item['class']
      item['class'] = item['class'].to_s

      pushed = false
      Sidekiq.client_middleware.invoke(worker_class, item, queue) do
        payload = MultiJson.dump(item)
        Sidekiq.redis do |conn|
          _, pushed = conn.multi do
            conn.sadd('queues', queue)
            conn.rpush("queue:#{queue}", payload)
          end
        end
      end
      !! pushed
    end

    # Redis compatibility helper.  Example usage:
    #
    #   Sidekiq::Client.enqueue(MyWorker, 'foo', 1, :bat => 'bar')
    #
    # Messages are enqueued to the 'default' queue.
    #
    def self.enqueue(klass, *args)
      push('class' => klass, 'args' => args)
    end
  end
end
