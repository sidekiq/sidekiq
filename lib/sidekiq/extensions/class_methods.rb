require 'sidekiq/extensions/generic_proxy'
require 'sidekiq/extensions/extension_handler'

module Sidekiq
  module Extensions
    ##
    # Adds 'delay', 'delay_for' and `delay_until` methods to all Classes to offload class method
    # execution to Sidekiq. The base of these methods can also be customized. Examples:
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
      include ExtensionHandler

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
