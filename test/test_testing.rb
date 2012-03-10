require 'helper'
require 'sidekiq/worker'
require 'active_record'
require 'action_mailer'
require 'sidekiq/extensions/action_mailer'
require 'sidekiq/extensions/active_record'

class TestTesting < MiniTest::Unit::TestCase
  describe 'sidekiq testing' do

    class DirectWorker
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
      require 'sidekiq/testing'
    end

    after do
      # Undo override
      Sidekiq::Worker::ClassMethods.class_eval do
        remove_method :perform_async
        alias_method :perform_async, :perform_async_old
        remove_method :perform_async_old
      end
    end

    it 'stubs the async call when in testing mode' do
      # We can only have one it block here so all 'testing' tests
      # have to go here because require 'sidekiq/testing' changes
      # how Sidekiq works and we need to roll back those changes
      # when the test is done.
      assert_equal 0, DirectWorker.jobs.size
      assert DirectWorker.perform_async(1, 2)
      assert_equal 1, DirectWorker.jobs.size

      assert_equal 0, Sidekiq::Extensions::DelayedMailer.jobs.size
      FooMailer.delay.bar('hello!')
      assert_equal 1, Sidekiq::Extensions::DelayedMailer.jobs.size

      assert_equal 0, Sidekiq::Extensions::DelayedModel.jobs.size
      FooModel.delay.bar('hello!')
      assert_equal 1, Sidekiq::Extensions::DelayedModel.jobs.size
    end

  end
end
