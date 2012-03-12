require 'multi_json'
require 'redis'

require 'sidekiq/redis_connection'
require 'sidekiq/middleware/chain'
require 'sidekiq/middleware/client/unique_jobs'

module Sidekiq
  class Client

    def self.middleware
      raise "Sidekiq::Client.middleware is now Sidekiq.client_middleware"
    end

    def self.default_middleware
      Middleware::Chain.new do |m|
        m.add Middleware::Client::UniqueJobs
      end
    end

    def self.registered_workers
      Sidekiq.redis.smembers('workers')
    end

    def self.registered_queues
      Sidekiq.redis.smembers('queues')
    end

    def self.queue_mappings
      @queue_mappings ||= {}
    end

    # Example usage:
    # Sidekiq::Client.push('my_queue', 'class' => MyWorker, 'args' => ['foo', 1, :bat => 'bar'])
    def self.push(queue=nil, item)
      raise(ArgumentError, "Message must be a Hash of the form: { 'class' => SomeClass, 'args' => ['bob', 1, :foo => 'bar'] }") unless item.is_a?(Hash)
      raise(ArgumentError, "Message must include a class and set of arguments: #{item.inspect}") if !item['class'] || !item['args']

      queue = queue || queue_mappings[item['class'].to_s] || 'default'

      item['class'] = item['class'].to_s if !item['class'].is_a?(String)

      pushed = false
      Sidekiq.client_middleware.invoke(item, queue) do
        payload = MultiJson.encode(item)
        Sidekiq.redis.with_connection do |conn|
          conn.multi do
            conn.sadd('queues', queue)
            conn.rpush("queue:#{queue}", payload)
          end
        end
        pushed = true
      end
      pushed
    end

    # Please use .push if possible instead.
    #
    # Example usage:
    #
    #   Sidekiq::Client.enqueue(MyWorker, 'foo', 1, :bat => 'bar')
    #
    # Messages are enqueued to the 'default' queue.
    #
    def self.enqueue(klass, *args)
      push(nil, { 'class' => klass.name, 'args' => args })
    end
  end
end
