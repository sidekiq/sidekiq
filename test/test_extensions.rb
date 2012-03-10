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
      Sidekiq.client_middleware.entries.clear
      Sidekiq.instance_variable_set(:@redis, MiniTest::Mock.new)
      @redis = Sidekiq.redis
    end

    class MyModel < ActiveRecord::Base
      def self.long_class_method
        raise "Should not be called!"
      end
    end

    it 'allows delayed exection of ActiveRecord class methods' do
      @redis.expect(:rpush, @redis, ['queue:default', "{\"class\":\"Sidekiq::Extensions::DelayedModel\",\"args\":[\"---\\n- !ruby/class 'TestExtensions::MyModel'\\n- :long_class_method\\n- []\\n\"]}"])
      MyModel.delay.long_class_method
      @redis.verify
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
      @redis.expect(:rpush, @redis, ['queue:default', "{\"class\":\"Sidekiq::Extensions::DelayedMailer\",\"args\":[\"---\\n- !ruby/class 'TestExtensions::UserMailer'\\n- :greetings\\n- - 1\\n  - 2\\n\"]}"])
      UserMailer.delay.greetings(1, 2)
      @redis.verify
    end

  end
end
