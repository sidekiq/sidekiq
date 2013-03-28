require 'helper'
require 'sidekiq'
require 'sidekiq/worker'
require 'active_record'
require 'action_mailer'
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
      EnqueuedWorker.jobs.clear
    end

    after do
      # Undo override
      (class << Sidekiq::Client; self; end).class_eval do
        remove_method :raw_push
        alias_method :raw_push, :raw_push_old
        remove_method :raw_push_old
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

    class Something
      def self.foo(x)
      end
    end

    it 'stubs the delay call on models' do
      assert_equal 0, Sidekiq::Extensions::DelayedClass.jobs.size
      Something.delay.foo(Date.today)
      assert_equal 1, Sidekiq::Extensions::DelayedClass.jobs.size
    end

    it 'stubs the enqueue call' do
      assert_equal 0, EnqueuedWorker.jobs.size
      assert Sidekiq::Client.enqueue(EnqueuedWorker, 1, 2)
      assert_equal 1, EnqueuedWorker.jobs.size
    end

    it 'stubs the enqueue_to call' do
      assert_equal 0, EnqueuedWorker.jobs.size
      assert Sidekiq::Client.enqueue_to('someq', EnqueuedWorker, 1, 2)
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

    it 'round trip serializes the job arguments' do
      assert StoredWorker.perform_async(:mike)
      job = StoredWorker.jobs.first
      assert_equal "mike", job['args'].first
      StoredWorker.clear
    end

    class FirstWorker
      include Sidekiq::Worker
      class_attribute :count
      self.count = 0
      def perform
        self.class.count += 1
      end
    end

    class SecondWorker
      include Sidekiq::Worker
      class_attribute :count
      self.count = 0
      def perform
        self.class.count += 1
      end
    end

    class ThirdWorker
      include Sidekiq::Worker
      class_attribute :count
      def perform
        FirstWorker.perform_async
        SecondWorker.perform_async
      end
    end

    it 'clears jobs across all workers' do
      Sidekiq::Worker.jobs.clear
      FirstWorker.count = 0
      SecondWorker.count = 0

      assert_equal 0, FirstWorker.jobs.size
      assert_equal 0, SecondWorker.jobs.size

      FirstWorker.perform_async
      SecondWorker.perform_async

      assert_equal 1, FirstWorker.jobs.size
      assert_equal 1, SecondWorker.jobs.size

      Sidekiq::Worker.clear_all

      assert_equal 0, FirstWorker.jobs.size
      assert_equal 0, SecondWorker.jobs.size

      assert_equal 0, FirstWorker.count
      assert_equal 0, SecondWorker.count
    end

    it 'drains jobs across all workers' do
      Sidekiq::Worker.jobs.clear
      FirstWorker.count = 0
      SecondWorker.count = 0

      assert_equal 0, FirstWorker.jobs.size
      assert_equal 0, SecondWorker.jobs.size

      assert_equal 0, FirstWorker.count
      assert_equal 0, SecondWorker.count

      FirstWorker.perform_async
      SecondWorker.perform_async

      assert_equal 1, FirstWorker.jobs.size
      assert_equal 1, SecondWorker.jobs.size

      Sidekiq::Worker.drain_all

      assert_equal 0, FirstWorker.jobs.size
      assert_equal 0, SecondWorker.jobs.size

      assert_equal 1, FirstWorker.count
      assert_equal 1, SecondWorker.count
    end

    it 'drains jobs across all workers even when workers create new jobs' do
      Sidekiq::Worker.jobs.clear
      FirstWorker.count = 0
      SecondWorker.count = 0

      assert_equal 0, ThirdWorker.jobs.size

      assert_equal 0, FirstWorker.count
      assert_equal 0, SecondWorker.count

      ThirdWorker.perform_async

      assert_equal 1, ThirdWorker.jobs.size

      Sidekiq::Worker.drain_all

      assert_equal 0, ThirdWorker.jobs.size

      assert_equal 1, FirstWorker.count
      assert_equal 1, SecondWorker.count
    end
  end
end
