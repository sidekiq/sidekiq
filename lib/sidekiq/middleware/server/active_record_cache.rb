module Sidekiq
  module Middleware
    module Server
      class ActiveRecordCache
        def call(*args, &block)
          ::ActiveRecord::Base.cache(&block)
        end
      end
    end
  end
end
