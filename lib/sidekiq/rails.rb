module Sidekiq
  def self.hook_rails!
    return if defined?(@delay_removed)

    ActiveSupport.on_load(:active_record) do
      include Sidekiq::Extensions::ActiveRecord
    end

    ActiveSupport.on_load(:action_mailer) do
      extend Sidekiq::Extensions::ActionMailer
    end

    Module.__send__(:include, Sidekiq::Extensions::Klass)
  end

  # Removes the generic aliases which MAY clash with names of already
  #  created methods by other applications. The methods `sidekiq_delay`,
  #  `sidekiq_delay_for` and `sidekiq_delay_until` can be used instead.
  def self.remove_delay!
    @delay_removed = true

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
    initializer 'sidekiq' do
      Sidekiq.hook_rails!
    end
  end if defined?(::Rails)
end
