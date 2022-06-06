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
  #   Sidekiq::CurrentAttributes.persist(Myapp::Current)
  #
  module CurrentAttributes
    class Save
      include Sidekiq::ClientMiddleware

      def initialize(cattr)
        @klass = cattr
      end

      def call(_, job, _, _)
        attrs = @klass.attributes
        if job.has_key?("cattr")
          job["cattr"].merge!(attrs)
        else
          job["cattr"] = attrs
        end
        yield
      end
    end

    class Load
      include Sidekiq::ServerMiddleware

      def initialize(cattr)
        @klass = cattr
      end

      def call(_, job, _, &block)
        if job.has_key?("cattr")
          @klass.set(job["cattr"], &block)
        else
          yield
        end
      end
    end

    def self.persist(klass)
      Sidekiq.configure_client do |config|
        config.client_middleware.add Save, klass
      end
      Sidekiq.configure_server do |config|
        config.client_middleware.add Save, klass
        config.server_middleware.add Load, klass
      end
    end
  end
end
