require 'sidekiq/extensions/generic_proxy'
require 'sidekiq/extensions/extension_handler'

module Sidekiq
  module Extensions
    ##
    # Adds 'delay', 'delay_for' and `delay_until` methods to ActiveRecord to offload instance method
    # execution to Sidekiq. The base of these methods can also be customized. Examples:
    #
    # User.recent_signups.each { |user| user.delay.mark_as_awesome }
    #
    # Please note, this is not recommended as this will serialize the entire
    # object to Redis.  Your Sidekiq jobs should pass IDs, not entire instances.
    # This is here for backwards compatibility with Delayed::Job only.
    class DelayedModel
      include Sidekiq::Worker

      def perform(yml)
        (target, method_name, args) = YAML.load(yml)
        target.send(method_name, *args)
      end
    end

    module ActiveRecord
      include ExtensionHandler

      private

      def sidekiq_delay(options={})
        Proxy.new(DelayedModel, self, options)
      end
      def sidekiq_delay_for(interval, options={})
        Proxy.new(DelayedModel, self, options.merge('at' => Time.now.to_f + interval.to_f))
      end
      def sidekiq_delay_until(timestamp, options={})
        Proxy.new(DelayedModel, self, options.merge('at' => timestamp.to_f))
      end
    end

  end
end
