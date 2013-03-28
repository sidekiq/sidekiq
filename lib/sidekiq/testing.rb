module Sidekiq

  class Client
    class << self
      alias_method :raw_push_old, :raw_push

      def raw_push(payloads)
        payloads.each do |job|
          job['class'].constantize.jobs << Sidekiq.load_json(Sidekiq.dump_json(job))
        end
        true
      end
    end
  end

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
    #   assert_equal :something, HardWorker.jobs[0]['args'][0]
    #
    #   assert_equal 0, Sidekiq::Extensions::DelayedMailer.jobs.size
    #   MyMailer.delay.send_welcome_email('foo@example.com')
    #   assert_equal 1, Sidekiq::Extensions::DelayedMailer.jobs.size
    #
    # You can also clear and drain all workers' jobs:
    #
    #   assert_equal 0, Sidekiq::Extensions::DelayedMailer.jobs.size
    #   assert_equal 0, Sidekiq::Extensions::DelayedModel.jobs.size
    #
    #   MyMailer.delay.send_welcome_email('foo@example.com')
    #   MyModel.delay.do_something_hard
    #
    #   assert_equal 1, Sidekiq::Extensions::DelayedMailer.jobs.size
    #   assert_equal 1, Sidekiq::Extensions::DelayedModel.jobs.size
    #
    #   Sidekiq::Worker.clear_all # or .drain_all
    #
    #   assert_equal 0, Sidekiq::Extensions::DelayedMailer.jobs.size
    #   assert_equal 0, Sidekiq::Extensions::DelayedModel.jobs.size
    #
    # This can be useful to make sure jobs don't linger between tests:
    #
    #   RSpec.configure do |config|
    #     config.before(:each) do
    #       Sidekiq::Worker.clear_all
    #     end
    #   end
    #
    # or for acceptance testing, i.e. with cucumber:
    #
    #   AfterStep do
    #     Sidekiq::Worker.drain_all
    #   end
    #
    #   When I sign up as "foo@example.com"
    #   Then I should receive a welcome email to "foo@example.com"
    #
    module ClassMethods

      # Jobs queued for this worker
      def jobs
        Worker.jobs[self]
      end

      # Clear all jobs for this worker
      def clear
        jobs.clear
      end

      # Drain and run all jobs for this worker
      def drain
        while job = jobs.shift do
          new.perform(*job['args'])
        end
      end
    end

    class << self
      def jobs # :nodoc:
        @jobs ||= Hash.new { |hash, key| hash[key] = [] }
      end

      # Clear all queued jobs across all workers
      def clear_all
        jobs.clear
      end

      # Drain all queued jobs across all workers
      def drain_all
        until jobs.values.all?(&:empty?) do
          jobs.keys.each(&:drain)
        end
      end
    end
  end
end
