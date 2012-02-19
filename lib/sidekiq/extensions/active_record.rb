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

      def perform(yml)
        (target, method_name, args) = YAML.load(yml)
        target.send(method_name, *args)
      end
    end

    module ActiveRecord
      def delay
        Proxy.new(DelayedModel, self)
      end
    end

    ::ActiveRecord::Base.extend(ActiveRecord)
    ::ActiveRecord::Base.send(:include, ActiveRecord)
  end
end if defined?(::ActiveRecord)
