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
    config.autoload_paths << File.expand_path("#{config.root}/app/workers") if File.exist?("#{config.root}/app/workers")

    initializer 'sidekiq' do
      Sidekiq.hook_rails!
    end
  end if defined?(::Rails)
end
