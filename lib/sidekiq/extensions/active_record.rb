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

      def perform(*msg)
        (target, method_name, args) = ArgsSerializer.deserialize_message(*msg)
        target.send(method_name, *args)
      end
    end

    module ActiveRecord
      module ClassMethods
        def sidekiq_deserialize(string)
          where(id: string.to_i).first
        end
      end
      
      module InstanceMethods
        def delay(options={})
          Proxy.new(DelayedModel, self, options)
        end
        def delay_for(interval, options={})
          options = options.reverse_merge(at: Time.now.to_f + interval.to_f)
          delay(options)
        end

        def sidekiq_serialize
          "SIDEKIQ@#{self.class.name}@#{self.id}"
        end
      end
      
      def self.included(receiver)
        receiver.extend         ClassMethods
        receiver.send :include, InstanceMethods
      end
    end

  end
end
