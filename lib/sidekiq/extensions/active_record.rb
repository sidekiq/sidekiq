require 'sidekiq/extensions/generic_proxy'

module Sidekiq
  module Extensions
    ##
    # Adds a 'delay' method to ActiveRecords to offload instance method
    # execution to Sidekiq.  Examples:
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
      def delay
        Proxy.new(DelayedModel, self)
      end
      def delay_for(interval)
        Proxy.new(DelayedModel, self, Time.now.to_f + interval.to_f)
      end
    end

  end
end
