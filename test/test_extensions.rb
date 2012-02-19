require 'helper'
require 'active_record'
require 'action_mailer'
require 'sidekiq'

class TestExtensions < MiniTest::Unit::TestCase
  describe 'sidekiq extensions' do
    before do
      Sidekiq.client_middleware.entries.clear
      Sidekiq.redis = @redis = MiniTest::Mock.new
      @redis.expect(:with_connection, @redis, [])
    end

    class MyModel < ActiveRecord::Base
      def self.long_class_method
        raise "Should not be called!"
      end
    end

    it 'allowed delayed exection of ActiveRecord class methods' do
      @redis.expect(:rpush, @redis, ['queue:default', "{\"class\":\"Sidekiq::Extensions::DelayedModel\",\"args\":[\"---\\n- !ruby/class 'TestExtensions::MyModel'\\n- :long_class_method\\n- []\\n\"]}"])
      MyModel.delay.long_class_method
    end

    it 'allows delayed exection of ActiveRecord instance methods' do
      skip('requires a database')
    end

    class UserMailer < ActionMailer::Base
      def greetings(a, b)
        raise "Should not be called!"
      end
    end

    it 'allowed delayed delivery of ActionMailer mails' do
      @redis.expect(:rpush, @redis, ['queue:default', "{\"class\":\"Sidekiq::Extensions::DelayedMailer\",\"args\":[\"---\\n- !ruby/class 'TestExtensions::UserMailer'\\n- :greetings\\n- - 1\\n  - 2\\n\"]}"])
      UserMailer.delay.greetings(1, 2)
    end

  end
end
