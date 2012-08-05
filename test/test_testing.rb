require 'helper'
require 'sidekiq'
require 'sidekiq/worker'
require 'active_record'
require 'action_mailer'
require 'timecop'
require 'sidekiq/rails'
require 'sidekiq/extensions/action_mailer'
require 'sidekiq/extensions/active_record'

Sidekiq.hook_rails!

class TestTesting < MiniTest::Unit::TestCase
  describe 'sidekiq testing' do
    class PerformError < RuntimeError; end

    class DirectWorker
      include Sidekiq::Worker
      def perform(a, b)
        a + b
      end
    end

    class EnqueuedWorker
      include Sidekiq::Worker
      def perform(a, b)
        a + b
      end
    end

    class StoredWorker
      include Sidekiq::Worker
      def perform(error)
        raise PerformError if error
      end
    end

    class ScheduledWorker
      include Sidekiq::Worker
      def perform(error)
        raise PerformError if error
      end
    end

    class FooMailer < ActionMailer::Base
      def bar(str)
        str
      end
    end

    class FooModel < ActiveRecord::Base
      def bar(str)
        str
      end
    end

    before do
      load 'sidekiq/testing.rb'
    end

    after do
      # Undo override
      Sidekiq::Worker::ClassMethods.class_eval do
        remove_method :client_push
        alias_method :client_push, :client_push_old
        remove_method :client_push_old
      end
    end

    it 'stubs the async call' do
      assert_equal 0, DirectWorker.jobs.size
      assert DirectWorker.perform_async(1, 2)
      assert_equal 1, DirectWorker.jobs.size
      assert DirectWorker.perform_in(10, 1, 2)
      assert_equal 2, DirectWorker.jobs.size
      assert DirectWorker.perform_at(10, 1, 2)
      assert_equal 3, DirectWorker.jobs.size
      assert_in_delta 10.seconds.from_now.to_f, DirectWorker.jobs.last['at'], 0.01
    end

    it 'stubs the delay call on mailers' do
      assert_equal 0, Sidekiq::Extensions::DelayedMailer.jobs.size
      FooMailer.delay.bar('hello!')
      assert_equal 1, Sidekiq::Extensions::DelayedMailer.jobs.size
    end

    it 'stubs the delay call on models' do
      assert_equal 0, Sidekiq::Extensions::DelayedModel.jobs.size
      FooModel.delay.bar('hello!')
      assert_equal 1, Sidekiq::Extensions::DelayedModel.jobs.size
    end

    it 'stubs the enqueue call' do
      assert_equal 0, EnqueuedWorker.jobs.size
      assert Sidekiq::Client.enqueue(EnqueuedWorker, 1, 2)
      assert_equal 1, EnqueuedWorker.jobs.size
    end

    it 'executes all stored jobs' do
      assert StoredWorker.perform_async(false)
      assert StoredWorker.perform_async(true)

      assert_equal 2, StoredWorker.jobs.size
      assert_raises PerformError do
        StoredWorker.drain
      end
      assert_equal 0, StoredWorker.jobs.size
    end

    it 'executes all scheduled jobs' do
      assert ScheduledWorker.perform_in(10, true)
      assert ScheduledWorker.perform_async(false)

      assert_equal 2, ScheduledWorker.jobs.size
      ScheduledWorker.drain_due_jobs
      assert_equal 1, ScheduledWorker.jobs.size

      Timecop.travel(Time.now + 5) do
        ScheduledWorker.drain_due_jobs
        assert_equal 1, ScheduledWorker.jobs.size
        Timecop.travel(Time.now + 5) do
          assert_raises PerformError do
            ScheduledWorker.drain_due_jobs
          end
          assert_equal 0, ScheduledWorker.jobs.size
        end
      end
    end
  end
end
