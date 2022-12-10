require "active_support/current_attributes"

module Sidekiq
  ##
  # Automatically save and load any current attributes in the execution context
  # so context attributes "flow" from Rails actions into any associated jobs.
  # This can be useful for multi-tenancy, i18n locale, timezone, any implicit
  # per-request attribute. See +ActiveSupport::CurrentAttributes+.
  #
  # @example
  #
  #   # in your initializer
  #   require "sidekiq/middleware/current_attributes"
  #   Sidekiq::CurrentAttributes.persist("Myapp::Current")
  #
  module CurrentAttributes
    class Save
      include Sidekiq::ClientMiddleware

      def initialize(cattr)
        @strklass = cattr
      end

      def call(_, job, _, _)
        if !job.has_key?("cattr")
          attrs = @strklass.constantize.attributes
          # Retries can push the job N times, we don't
          # want retries to reset cattr. #5692, #5090
          job["cattr"] = attrs if attrs.any?
        end
        yield
      end
    end

    class Load
      include Sidekiq::ServerMiddleware

      def initialize(cattr)
        @strklass = cattr
      end

      def call(_, job, _, &block)
        if job.has_key?("cattr")
          @strklass.constantize.set(job["cattr"], &block)
        else
          yield
        end
      end
    end

    def self.persist(klass, config = Sidekiq.default_configuration)
      config.client_middleware.add Save, klass.to_s
      config.server_middleware.add Load, klass.to_s
    end
  end
end
