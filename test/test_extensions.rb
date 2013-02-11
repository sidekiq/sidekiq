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

    it 'uses and stringifies specified options' do
      assert_equal [], Sidekiq::Client.registered_queues
      assert_equal 0, Sidekiq.redis {|c| c.llen('queue:notdefault') }
      MyModel.delay(queue: :notdefault).long_class_method
      assert_equal ['notdefault'], Sidekiq::Client.registered_queues
      assert_equal 1, Sidekiq.redis {|c| c.llen('queue:notdefault') }
    end

    it 'allows delayed scheduling of AR class methods' do
      assert_equal 0, Sidekiq.redis {|c| c.zcard('schedule') }
      MyModel.delay_for(5.days).long_class_method
      assert_equal 1, Sidekiq.redis {|c| c.zcard('schedule') }
    end

    it 'allows until delayed scheduling of AR class methods' do
      assert_equal 0, Sidekiq.redis {|c| c.zcard('schedule') }
      MyModel.delay_until(1.day.from_now).long_class_method
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

    it 'allows until delay scheduling of AM mails' do
      assert_equal 0, Sidekiq.redis {|c| c.zcard('schedule') }
      UserMailer.delay_until(5.days.from_now).greetings(1, 2)
      assert_equal 1, Sidekiq.redis {|c| c.zcard('schedule') }
    end

    class SomeClass
      def self.doit(arg)
      end
    end

    it 'allows delay of any ole class method' do
      assert_equal 0, queue_size
      SomeClass.delay.doit(Date.today)
      assert_equal 1, queue_size
    end

    module SomeModule
      def self.doit(arg)
      end
    end

    it 'allows delay of any module class method' do
      assert_equal 0, queue_size
      SomeModule.delay.doit(Date.today)
      assert_equal 1, queue_size
    end

    def queue_size(name='default')
      Sidekiq::Queue.new(name).size
    end
  end

end
