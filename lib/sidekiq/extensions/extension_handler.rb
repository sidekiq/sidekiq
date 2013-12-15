module Sidekiq
  module Extensions
    module ExtensionHandler
      # Intercepts method calls to wherever this module is included and checks to see
      # if the method calls matches our delayed extension base (if enabled). If delayed
      # extensions are disabled, we immediately call super. Otherwise, we check for a match.
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