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
        remove_method :perform_async
        alias_method :perform_async, :perform_async_old
        remove_method :perform_async_old
      end
    end

    it 'stubs the async call' do
      assert_equal 0, DirectWorker.jobs.size
      assert DirectWorker.perform_async(1, 2)
      assert_equal 1, DirectWorker.jobs.size
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
  end
end
