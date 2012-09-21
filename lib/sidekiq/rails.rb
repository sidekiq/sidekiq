module Sidekiq
  def self.hook_rails!
    if defined?(::ActiveRecord)
      ::ActiveRecord::Base.send(:include, Sidekiq::Extensions::ActiveRecord)
    end

    if defined?(::ActionMailer)
      ::ActionMailer::Base.extend(Sidekiq::Extensions::ActionMailer)
    end
  end

  class Rails < ::Rails::Engine
    config.autoload_paths << File.expand_path("#{config.root}/app/workers") if File.exist?("#{config.root}/app/workers")

    initializer 'sidekiq' do
      Sidekiq.hook_rails!
    end
  end if defined?(::Rails)
end
