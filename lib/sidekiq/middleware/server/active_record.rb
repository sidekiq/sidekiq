module Sidekiq
  module Middleware
    module Server
      class ActiveRecord
        def call(*args)
          yield
        ensure
          ::ActiveRecord::Base.clear_active_connections! if defined?(::ActiveRecord)
        end
      end
    end
  end
end
