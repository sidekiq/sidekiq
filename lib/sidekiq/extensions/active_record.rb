require 'sidekiq/extensions/generic_proxy'

module Sidekiq
  module Extensions
    ##
    # Adds a 'delay' method to ActiveRecord to offload arbitrary method
    # execution to Sidekiq.  Examples:
    #
    # User.delay.delete_inactive
    # User.recent_signups.each { |user| user.delay.mark_as_awesome }
    class DelayedModel
      include Sidekiq::Worker

      def perform(marshal, method_name, args)
        target = ::Marshal.load(marshal)
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
