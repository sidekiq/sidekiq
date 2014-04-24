module Sidekiq
  def self.hook_rails!
    ActiveSupport.on_load(:active_record) do
      include Sidekiq::Extensions::ActiveRecord
    end

    ActiveSupport.on_load(:action_mailer) do
      extend Sidekiq::Extensions::ActionMailer
    end
  end

  # Removes the generic aliases which MAY clash with names of already
  #  created methods by other applications. The methods `sidekiq_delay`,
  #  `sidekiq_delay_for` and `sidekiq_delay_until` can be used instead.
  def self.namespace_delay_methods
    [Extensions::ActiveRecord, 
     Extensions::ActionMailer, 
     Extensions::Klass].each do |mod|
      mod.module_eval do
        remove_method :delay if respond_to?(:delay)
        remove_method :delay_for if respond_to?(:delay_for)
        remove_method :delay_until if respond_to?(:delay_until)
      end
    end
  end

  class Rails < ::Rails::Engine
    config.autoload_paths << File.expand_path("#{config.root}/app/workers") if File.exist?("#{config.root}/app/workers")

    initializer 'sidekiq' do
      Sidekiq.hook_rails!
    end
  end if defined?(::Rails)
end
