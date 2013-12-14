module Sidekiq
  module Extensions
    module ExtensionHandler
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
    end
  end
end