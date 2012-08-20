require 'helper'
require 'sidekiq'
require 'active_record'
require 'action_mailer'
require 'sidekiq/extensions/action_mailer'
require 'sidekiq/extensions/active_record'
require 'sidekiq/rails'

Sidekiq.hook_rails!

class TestExtensions < MiniTest::Unit::TestCase
  describe 'sidekiq extensions' do
    before do
      Sidekiq.redis = REDIS
      Sidekiq.redis {|c| c.flushdb }
    end

    class MyModel < ActiveRecord::Base
      def self.long_class_method
        raise "Should not be called!"
      end
    end

    it 'allows delayed execution of ActiveRecord class methods' do
      assert_equal [], Sidekiq::Client.registered_queues
      assert_equal 0, Sidekiq.redis {|c| c.llen('queue:default') }
      MyModel.delay.long_class_method
      assert_equal ['default'], Sidekiq::Client.registered_queues
      assert_equal 1, Sidekiq.redis {|c| c.llen('queue:default') }
    end

    it 'allows delayed scheduling of AR class methods' do
      assert_equal 0, Sidekiq.redis {|c| c.zcard('schedule') }
      MyModel.delay_for(5.days).long_class_method
      assert_equal 1, Sidekiq.redis {|c| c.zcard('schedule') }
    end

    class UserMailer < ActionMailer::Base
      def greetings(a, b)
        raise "Should not be called!"
      end
    end

    it 'allows delayed delivery of ActionMailer mails' do
      assert_equal [], Sidekiq::Client.registered_queues
      assert_equal 0, Sidekiq.redis {|c| c.llen('queue:default') }
      UserMailer.delay.greetings(1, 2)
      assert_equal ['default'], Sidekiq::Client.registered_queues
      assert_equal 1, Sidekiq.redis {|c| c.llen('queue:default') }
    end

    it 'allows delayed scheduling of AM mails' do
      assert_equal 0, Sidekiq.redis {|c| c.zcard('schedule') }
      UserMailer.delay_for(5.days).greetings(1, 2)
      assert_equal 1, Sidekiq.redis {|c| c.zcard('schedule') }
    end

    class SomeClass
      def self.doit(arg)
      end
    end

    it 'allows delay of any ole class method' do
      SomeClass.delay.doit(Date.today)
    end
  end

  describe 'sidekiq rails extensions configuration' do
    before do
      @options = Sidekiq.options
    end

    after do
      Sidekiq.options = @options
    end

    it 'should set enable_rails_extensions option to true by default' do
      assert Sidekiq.options[:enable_rails_extensions]
    end

    it 'should extend ActiveRecord and ActiveMailer if enable_rails_extensions is true' do
      assert Sidekiq.hook_rails!
    end

    it 'should not extend ActiveRecord and ActiveMailer if enable_rails_extensions is false' do
      Sidekiq.options = { :enable_rails_extensions => false }
      refute Sidekiq.hook_rails!
    end
  end
end
