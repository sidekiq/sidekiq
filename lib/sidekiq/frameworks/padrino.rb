module Sidekiq
  def self.hook_padrino!
    if defined?(::ActiveRecord)
      ::ActiveRecord::Base.send(:include, Sidekiq::Extensions::ActiveRecord)
    end

    # Do this for Padrino mailer?
    # if defined?(::ActionMailer)
    #   ::ActionMailer::Base.extend(Sidekiq::Extensions::ActionMailer)
    # end

    # Load Sidekiq workers if any
    ::Padrino.require_dependencies Dir[::Padrino.root('app', 'workers', '**', '*.rb')] if File.exist?(::Padrino.root('app', 'workers'))

    # Load mounted apps
    ::Padrino.mounted_apps.each do |app|
      puts "=> Loading Application #{app.app_class}"
      app.app_obj.setup_application!
    end
  end
end
