require 'multi_json'
require 'redis'

require 'sidekiq/redis_connection'
require 'sidekiq/middleware/chain'
require 'sidekiq/middleware/client/resque_web_compatibility'
require 'sidekiq/middleware/client/unique_jobs'

module Sidekiq
  class Client

    def self.middleware
      @middleware ||= begin
        m = Middleware::Chain.new
        m.register do
          use Middleware::Client::UniqueJobs, Client.redis
          use Middleware::Client::ResqueWebCompatibility, Client.redis
        end
        m
      end
    end

    def self.queues
      self.redis.smembers('queues')
    end

    def self.redis
      @redis ||= RedisConnection.create
    end

    def self.redis=(redis)
      @redis = redis
    end

    # Example usage:
    # Sidekiq::Client.push('my_queue', 'class' => MyWorker, 'args' => ['foo', 1, :bat => 'bar'])
    def self.push(queue=nil, item)
      raise(ArgumentError, "Message must be a Hash of the form: { 'class' => SomeClass, 'args' => ['bob', 1, :foo => 'bar'] }") unless item.is_a?(Hash)
      raise(ArgumentError, "Message must include a class and set of arguments: #{item.inspect}") if !item['class'] || !item['args']

      queue = queue || queues[item['class'].to_s] || 'default'

      item['class'] = item['class'].to_s if !item['class'].is_a?(String)

      pushed = false
      middleware.invoke(item, queue) do
        redis.rpush("queue:#{queue}", MultiJson.encode(item))
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
