require 'sidekiq/extensions/generic_proxy'

module Sidekiq
  module Extensions
    ##
    # Adds 'delay', 'delay_for' and `delay_until` methods to all Classes to offload class method
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
      def method_missing(method, *args, &block)
        return super if Sidekiq.delayed_extension_options['enabled'] == false
        
        method_name = method.to_s
        if method_name == Sidekiq.delayed_extension_options['base']
          sidekiq_delay(*args)
        elsif method_name == Sidekiq.delayed_extension_options['base'] + '_for'
          sidekiq_delay_for(*args)
        elsif method_name == Sidekiq.delayed_extension_options['base'] + '_until'
          sidekiq_delay_until(*args)
        else
          super
        end
      end

      private

      def sidekiq_delay(options={})
        Proxy.new(DelayedClass, self, options)
      end
      def sidekiq_delay_for(interval, options={})
        Proxy.new(DelayedClass, self, options.merge('at' => Time.now.to_f + interval.to_f))
      end
      def sidekiq_delay_until(timestamp, options={})
        Proxy.new(DelayedClass, self, options.merge('at' => timestamp.to_f))
      end
    end

  end
end

Module.send(:include, Sidekiq::Extensions::Klass)
