require 'securerandom'
require 'sidekiq'

module Sidekiq

  class Testing
    class << self
      attr_accessor :__test_mode

      def __set_test_mode(mode)
        if block_given?
          current_mode = self.__test_mode
          begin
            self.__test_mode = mode
            yield
          ensure
            self.__test_mode = current_mode
          end
        else
          self.__test_mode = mode
        end
      end

      def disable!(&block)
        __set_test_mode(:disable, &block)
      end

      def fake!(&block)
        __set_test_mode(:fake, &block)
      end

      def inline!(&block)
        __set_test_mode(:inline, &block)
      end

      def enabled?
        self.__test_mode != :disable
      end

      def disabled?
        self.__test_mode == :disable
      end

      def fake?
        self.__test_mode == :fake
      end

      def inline?
        self.__test_mode == :inline
      end
    end
  end

  # Default to fake testing to keep old behavior
  Sidekiq::Testing.fake!

  class EmptyQueueError < RuntimeError; end

  class Client
    alias_method :raw_push_real, :raw_push

    def raw_push(payloads)
      if Sidekiq::Testing.fake?
        payloads.each do |job|
          job['class'].constantize.jobs << Sidekiq.load_json(Sidekiq.dump_json(job))
        end
        true
      elsif Sidekiq::Testing.inline?
        payloads.each do |job|
          job['jid'] ||= SecureRandom.hex(12)
          klass = job['class'].constantize
          klass.jobs.unshift Sidekiq.load_json(Sidekiq.dump_json(job))
          klass.perform_one
        end
        true
      else
        raw_push_real(payloads)
      end
    end
  end

  module Job
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
    #   assert_equal 0, HardJob.jobs.size
    #   HardJob.perform_async(:something)
    #   assert_equal 1, HardJob.jobs.size
    #   assert_equal :something, HardJob.jobs[0]['args'][0]
    #
    #   assert_equal 0, Sidekiq::Extensions::DelayedMailer.jobs.size
    #   MyMailer.delay.send_welcome_email('foo@example.com')
    #   assert_equal 1, Sidekiq::Extensions::DelayedMailer.jobs.size
    #
    # You can also clear and drain all enqueued jobs:
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
    #   Sidekiq::Job.clear_all # or .drain_all
    #
    #   assert_equal 0, Sidekiq::Extensions::DelayedMailer.jobs.size
    #   assert_equal 0, Sidekiq::Extensions::DelayedModel.jobs.size
    #
    # This can be useful to make sure jobs don't linger between tests:
    #
    #   RSpec.configure do |config|
    #     config.before(:each) do
    #       Sidekiq::Job.clear_all
    #     end
    #   end
    #
    # or for acceptance testing, i.e. with cucumber:
    #
    #   AfterStep do
    #     Sidekiq::Job.drain_all
    #   end
    #
    #   When I sign up as "foo@example.com"
    #   Then I should receive a welcome email to "foo@example.com"
    #
    module ClassMethods

      # Jobs queued for this job type
      def jobs
        Job.jobs[self]
      end

      # Clear all jobs for this job type
      def clear
        jobs.clear
      end

      # Drain and run all jobs for this job type
      def drain
        while job = jobs.shift do
          worker = new
          worker.jid = job['jid']
          execute_job(worker, job['args'])
        end
      end

      # Pop out a single job and perform it
      def perform_one
        raise(EmptyQueueError, "perform_one called with empty job queue") if jobs.empty?
        msg = jobs.shift
        job = new
        job.jid = msg['jid']
        execute_job(job, msg['args'])
      end

      def execute_job(job, args)
        job.perform(*args)
      end
    end

    class << self
      def jobs # :nodoc:
        @jobs ||= Hash.new { |hash, key| hash[key] = [] }
      end

      # Clear all queued jobs across all job types
      def clear_all
        jobs.clear
      end

      # Drain all queued jobs across all job types
      def drain_all
        until jobs.values.all?(&:empty?) do
          jobs.keys.each(&:drain)
        end
      end
    end
  end
end
