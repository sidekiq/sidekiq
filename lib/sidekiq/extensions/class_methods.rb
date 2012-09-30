require 'sidekiq/extensions/generic_proxy'

module Sidekiq
  module Extensions
    ##
    # Adds a 'delay' method to all Classes to offload class method
    # execution to Sidekiq.  Examples:
    #
    # User.delay.delete_inactive
    # Wikipedia.delay.download_changes_for(Date.today)
    #
    class DelayedClass
      include Sidekiq::Worker

      def perform(yml)
        (target, method_name, args) = YAML.load(yml)
        target.send(method_name, *args)
      end
    end

    module Klass
      def delay
        Proxy.new(DelayedClass, self)
      end
      def delay_for(interval)
        Proxy.new(DelayedClass, self, Time.now.to_f + interval.to_f)
      end
    end

  end
end

Module.send(:include, Sidekiq::Extensions::Klass)
