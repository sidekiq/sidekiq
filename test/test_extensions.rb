require 'helper'
require 'sidekiq'
require 'active_record'
require 'action_mailer'
require 'sidekiq/extensions/action_mailer'
require 'sidekiq/extensions/active_record'

Sidekiq.hook_rails!

class TestExtensions < MiniTest::Unit::TestCase
  describe 'sidekiq extensions' do
    before do
      Sidekiq.redis = REDIS
      Sidekiq.redis.flushdb
    end

    class MyModel < ActiveRecord::Base
      def self.long_class_method
        raise "Should not be called!"
      end
    end

    it 'allows delayed exection of ActiveRecord class methods' do
      assert_equal [], Sidekiq::Client.registered_queues
      assert_equal 0, Sidekiq.redis.llen('queue:default')
      MyModel.delay.long_class_method
      assert_equal ['default'], Sidekiq::Client.registered_queues
      assert_equal 1, Sidekiq.redis.llen('queue:default')
    end

    it 'allows delayed exection of ActiveRecord instance methods' do
      skip('requires a database')
    end

    class UserMailer < ActionMailer::Base
      def greetings(a, b)
        raise "Should not be called!"
      end
    end

    it 'allows delayed delivery of ActionMailer mails' do
      assert_equal [], Sidekiq::Client.registered_queues
      assert_equal 0, Sidekiq.redis.llen('queue:default')
      UserMailer.delay.greetings(1, 2)
      assert_equal ['default'], Sidekiq::Client.registered_queues
      assert_equal 1, Sidekiq.redis.llen('queue:default')
    end

  end
end
