module Sidekiq
  module Extensions

    def self.enable_delay!
      if defined?(::ActiveSupport)
        ActiveSupport.on_load(:active_record) do
          require 'sidekiq/extensions/active_record'
          include Sidekiq::Extensions::ActiveRecord
        end
        ActiveSupport.on_load(:action_mailer) do
          require 'sidekiq/extensions/action_mailer'
          extend Sidekiq::Extensions::ActionMailer
        end
      end

      require 'sidekiq/extensions/class_methods'
      Module.__send__(:include, Sidekiq::Extensions::Klass)
    end

  end
end
