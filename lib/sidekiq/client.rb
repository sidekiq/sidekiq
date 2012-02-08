require 'multi_json'
require 'redis'

require 'sidekiq/redis_connection'
require 'sidekiq/middleware/chain'
require 'sidekiq/middleware/client/unique_jobs'

module Sidekiq
  class Client
    def self.middleware
      @middleware ||= Middleware::Chain.new
    end

    def self.redis
      @redis ||= begin
        RedisConnection.create
      end
    end

    def self.redis=(redis)
      @redis = redis
    end

    def self.ignore_duplicate_jobs=(value)
      @ignore_duplicate_jobs = value
      if @ignore_duplicate_jobs
        middleware.register do
          use Middleware::Client::UniqueJobs, Client.redis
        end
      else
        middleware.unregister(Middleware::Client::UniqueJobs)
      end
    end

    # Example usage:
    # Sidekiq::Client.push('my_queue', 'class' => MyWorker, 'args' => ['foo', 1, :bat => 'bar'])
    def self.push(queue='default', item)
      raise(ArgumentError, "Message must be a Hash of the form: { 'class' => SomeClass, 'args' => ['bob', 1, :foo => 'bar'] }") unless item.is_a?(Hash)
      raise(ArgumentError, "Message must include a class and set of arguments: #{item.inspect}") if !item['class'] || !item['args']

      item['class'] = item['class'].to_s if !item['class'].is_a?(String)
      middleware.invoke(item) do
        redis.rpush("queue:#{queue}", MultiJson.encode(item))
      end
    end

    # Please use .push if possible instead.
    #
    # Example usage:
    #
    #   Sidekiq::Client.enqueue(MyWorker, 'foo', 1, :bat => 'bar')
    #
    # Messages are enqueued to the 'default' queue.  Optionally,
    # MyWorker can define a queue class method:
    #
    #   def self.queue
    #     'my_queue'
    #   end
    #
    def self.enqueue(klass, *args)
      queue = (klass.respond_to?(:queue) && klass.queue) || 'default'
      push(queue, { 'class' => klass.name, 'args' => args })
    end
  end
end
