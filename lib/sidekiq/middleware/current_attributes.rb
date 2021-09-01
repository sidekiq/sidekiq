require "active_support/current_attributes"

module Sidekiq
  # Automatically save and load any current attributes in the execution context
  # so the context "flows" from a Rails controller into any associated job execution.
  # See ActiveSupport::CurrentAttributes. Usage:
  #
  # require "sidekiq/middleware/context"
  # Sidekiq::CurrentAttributes.persist(Myapp::Current)
  #
  module CurrentAttributes
    class Save
      def initialize(with:)
        @klass = with
      end

      def call(_, job, _, _)
        job["ctx"] = @klass.attributes
        yield
      end
    end

    class Load
      def initialize(with:)
        @klass = with
      end

      def call(_, job, _, _, &block)
        @klass.set(job["ctx"], &block)
      end
    end

    def self.persist(klass)
      Sidekiq.configure_client do |config|
        config.client_middleware.add Save, with: klass
      end
      Sidekiq.configure_server do |config|
        config.client_middleware.add Save, with: klass
        config.server_middleware.add Load, with: klass
      end
    end
  end
end
