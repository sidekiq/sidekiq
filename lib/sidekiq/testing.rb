module Sidekiq
  module Worker
    module ClassMethods
      alias_method :perform_async_old, :perform_async
      def perform_async(*args)
        self.new.perform(*args)
      end
    end
  end
end
