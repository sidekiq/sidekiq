module Sidekiq
  module Framework
    module Padrino
      def self.hook!
        # Load Sidekiq workers if any
        ::Padrino.require_dependencies Dir[::Padrino.root('app', 'workers', '**', '*.rb')] if File.exist?(::Padrino.root('app', 'workers'))

        # Load mounted apps
        ::Padrino.mounted_apps.each do |app|
          puts "=> Loading Application #{app.app_class}"
          app.app_obj.setup_application!
        end

        # FIXME For some reason this isn't making it there!..
        # We need to tell why... :(
        # At the moment the solution is to put it on an after_load!
        if defined?(::ActiveRecord)
          ::ActiveRecord::Base.send(:include, Sidekiq::Extensions::ActiveRecord)
        end
      end
    end
  end
end
