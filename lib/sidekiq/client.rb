require 'multi_json'
require 'redis'
require 'base64'

module Sidekiq
  class Client

    class << self
      attr_accessor :ignore_duplicate_jobs
      alias_method :ignore_duplicate_jobs?, :ignore_duplicate_jobs
    end

    def self.redis
      @redis ||= begin
        # autoconfig for Heroku
        hash = {}
        hash[:url] = ENV['REDISTOGO_URL'] if ENV['REDISTOGO_URL']
        Redis.connect(hash)
      end
    end

    def self.redis=(redis)
      @redis = redis
    end

    # Example usage:
    # Sidekiq::Client.push('my_queue', 'class' => MyWorker, 'args' => ['foo', 1, :bat => 'bar'])
    def self.push(queue='default', item)
      raise(ArgumentError, "Message must be a Hash of the form: { 'class' => SomeClass, 'args' => ['bob', 1, :foo => 'bar'] }") unless item.is_a?(Hash)
      raise(ArgumentError, "Message must include a class and set of arguments: #{item.inspect}") if !item['class'] || !item['args']

      item['class'] = item['class'].to_s if !item['class'].is_a?(String)
      queue_key = "queue:#{queue}"
      encoded_payloads_key = "queue:encoded:#{queue}"
      payload = MultiJson.encode(item)
      encoded_payload = Base64.encode64(payload)
      return if ignore_duplicate_jobs? && already_queued?(encoded_payloads_key, encoded_payload)

      redis.multi do
        redis.sadd(encoded_payloads_key, encoded_payload)
        redis.rpush(queue_key, payload)
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

    def self.already_queued?(queue_key, encoded_payload)
      redis.sismember(queue_key, encoded_payload)
    end
  end
end
