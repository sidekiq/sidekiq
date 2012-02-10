module Sidekiq
  module Worker
    module ClassMethods
      def perform_async(*args)
        self.new.perform(*args)
      end
    end
  end
end
