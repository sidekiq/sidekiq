module Sidekiq
  def self.hook_rails!
    ActiveSupport.on_load(:active_record) do
      include Sidekiq::Extensions::ActiveRecord
    end

    ActiveSupport.on_load(:action_mailer) do
      extend Sidekiq::Extensions::ActionMailer
    end
  end

  class Rails < ::Rails::Engine
    initializer 'sidekiq' do
      Sidekiq.hook_rails!
    end
  end if defined?(::Rails)
end
