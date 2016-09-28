module Sidekiq
  module Middleware
    module Server
      class ActiveRecord
        def call(*args)
          yield
        ensure
          # We can't use this middleware with the Rails reloader.
          #
          # The reloader needs the active connection to clear its query cache
          # before releasing it otherwise other workers will see dirty query
          # cache data. The reloader will then take care of clearing
          # ActiveRecord connections as well.
          #
          # We need to make sure folks remove this middleware if they've added
          # it themselves.
          #
          if defined?(Sidekiq::Rails::Reloader) && Sidekiq.options[:reloader].is_a?(Sidekiq::Rails::Reloader)
            raise ArgumentError, "Your are usign the Sidekiq ActiveRecord middleware and the new Rails 5 reloader which are incompatible. Please remove the ActiveRecord middleware from your Sidekiq middleware configuration."
          else
            ::ActiveRecord::Base.clear_active_connections!
          end
        end
      end
    end
  end
end
