require 'multi_json'

module Sidekiq
  class Client

    def self.redis
      @redis ||= Redis.new
    end

    def self.redis=(redis)
      @redis = redis
    end

    # Example usage:
    # Sidekiq::Client.push('my_queue', :class => MyWorker, :args => ['foo', 1, :bat => 'bar'])
    def self.push(queue, item)
      raise(ArgumentError, "Message must be a Hash of the form: { :class => SomeClass, :args => ['bob', 1, :foo => 'bar'] }") unless item.is_a?(Hash)
      raise(ArgumentError, "Message must include a class and set of arguments: #{item.inspect}") if !item[:class] || !item[:args]

      item[:class] = item[:class].to_s if !item[:class].is_a?(String)
      redis.rpush("queue:#{queue}", MultiJson.encode(item))
    end

    # Please use .push if possible instead.
    #
    # Example usage:
    #
    #   Sidekiq::Client.enqueue(MyWorker, 'foo', 1, :bat => 'bar')
    #
    # where MyWorker has defined:
    #
    #   def self.queue
    #     'my_queue'
    #   end
    #
    def self.enqueue(klass, *args)
      queue = klass.instance_variable_get(:@queue) || (klass.respond_to?(:queue) && klass.queue) || raise(ArgumentError, "Cannot determine queue to use")
      push(queue, { 'class' => klass.name, 'args' => args })
    end
  end
end
