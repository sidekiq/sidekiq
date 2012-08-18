module Sidekiq
  module Worker

    ##
    # The Sidekiq inline infrastructure overrides the perform_async so that it
    # actually calls perform instead. This allows workers to be run inline in a
    # testing environment.
    #
    # This is similar to `Resque.inline = true` functionality.
    #
    # Example:
    #
    #   require 'sidekiq/testing/inline'
    #
    #   $external_variable = 0
    #
    #   class ExternalWorker
    #     include Sidekiq::Worker
    #
    #     def perform
    #       $external_variable = 1
    #     end
    #   end
    #
    #   assert_equal 0, $external_variable
    #   ExternalWorker.perform_async
    #   assert_equal 1, $external_variable
    #
    module ClassMethods
      alias_method :perform_async_old, :perform_async
      def perform_async(*args)
        new.perform(*
          Sidekiq::Extensions::ArgsSerializer.deserialize(
            Sidekiq::Extensions::ArgsSerializer.serialize(args)
          )
        )
        true
      end

      alias_method :perform_async_with_options_old, :perform_async_with_options
      def perform_async_with_options(options, *args)
        new.perform(*
          Sidekiq::Extensions::ArgsSerializer.deserialize(
            Sidekiq::Extensions::ArgsSerializer.serialize(args)
          )
        )
        true
      end
    end
  end
end
