module Sidekiq
  module Worker

    ##
    # The Sidekiq testing infrastructure overrides perform_async
    # so that it does not actually touch the network.  Instead it
    # stores the asynchronous jobs in a per-class array so that
    # their presence/absence can be asserted by your tests.
    #
    # This is similar to ActionMailer's :test delivery_method and its
    # ActionMailer::Base.deliveries array.
    #
    # Example:
    #
    #   require 'sidekiq/testing'
    #
    #   assert_equal 0, HardWorker.jobs.size
    #   HardWorker.perform_async(:something)
    #   assert_equal 1, HardWorker.jobs.size
    #   assert HardWorker.has_queued?(:something)
    #
    #   assert_equal 0, Sidekiq::Extensions::DelayedMailer.jobs.size
    #   MyMailer.delayed.send_welcome_email('foo@example.com')
    #   assert_equal 1, Sidekiq::Extensions::DelayedMailer.jobs.size
    #
    module ClassMethods
      alias_method :client_push_old, :client_push
      def client_push(opts)
        jobs << opts
        true
      end

      def jobs
        @pushed ||= []
      end

      def perform_next
        job = jobs.shift
        new.perform(*job['args']) if job
        job
      end

      def drain
        while perform_next do; end
      end

      def has_queued?(*args)
        jobs.any? { |job| job['args'] == args }
      end
    end
  end
end
