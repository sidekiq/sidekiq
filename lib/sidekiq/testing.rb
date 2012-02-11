module Sidekiq
  module Worker

    ##
    # The Sidekiq testing infrastructure just overrides perform_async
    # so that it does not actually touch the network.  Instead it
    # just stores the asynchronous jobs in a per-class array so that
    # their presence/absence can be asserted by your tests.
    #
    # This is similar to ActionMailer's :test delivery_method and its
    # ActionMailer::Base.deliveries array.
    module ClassMethods
      alias_method :perform_async_old, :perform_async
      def perform_async(*args)
        jobs << args
        true
      end

      def jobs
        @pushed ||= []
      end
    end
  end
end
