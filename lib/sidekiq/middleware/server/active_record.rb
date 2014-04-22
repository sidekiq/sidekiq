module Sidekiq
  module Middleware
    module Server
      class ActiveRecord
        def call(*args)
          yield
        ensure
          if defined?(::ActiveRecord::Base) && ::ActiveRecord::Base.respond_to?(:clear_active_connections!)
            ::ActiveRecord::Base.clear_active_connections!
          end
        end
      end
    end
  end
end
