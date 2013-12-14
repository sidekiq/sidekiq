require 'helper'
require 'sidekiq'
require 'active_record'
require 'action_mailer'
require 'sidekiq/extensions/action_mailer'
require 'sidekiq/extensions/active_record'
require 'sidekiq/rails'

Sidekiq.hook_rails!

class TestExtensions < Sidekiq::Test
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
      assert_equal [], Sidekiq::Queue.all.map(&:name)
      assert_equal 0, Sidekiq.redis {|c| c.llen('queue:default') }
      MyModel.delay.long_class_method
      assert_equal ['default'], Sidekiq::Queue.all.map(&:name)
      assert_equal 1, Sidekiq.redis {|c| c.llen('queue:default') }
    end

    it 'uses and stringifies specified options' do
      assert_equal [], Sidekiq::Queue.all.map(&:name)
      assert_equal 0, Sidekiq.redis {|c| c.llen('queue:notdefault') }
      MyModel.delay(queue: :notdefault).long_class_method
      assert_equal ['notdefault'], Sidekiq::Queue.all.map(&:name)
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
      assert_equal [], Sidekiq::Queue.all.map(&:name)
      assert_equal 0, Sidekiq.redis {|c| c.llen('queue:default') }
      UserMailer.delay.greetings(1, 2)
      assert_equal ['default'], Sidekiq::Queue.all.map(&:name)
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

    describe 'when disbaled' do
      before do
        Sidekiq.delayed_extension_options = { 'enabled' => false }
      end

      after do
        Sidekiq.delayed_extension_options = { 'enabled' => true }
      end

      it 'does not delay when disabled on class methods' do
        lambda {
          SomeClass.delay.doit(Date.today)
        }.must_raise(NoMethodError)
      end

      it 'does not delay when disabled on module class methods' do
        lambda {
          SomeModule.delay.doit(Date.today)
        }.must_raise(NoMethodError)
      end

      it 'does not allow delayed scheduling' do
        lambda {
          SomeClass.delay_for(5.days).long_class_method
        }.must_raise(NoMethodError)
      end

      it 'does not allow until delayed scheduling' do
        lambda {
          SomeClass.delay_until(1.day.from_now).long_class_method
        }.must_raise(NoMethodError)
      end

      it 'does not delay when disabled on ActiveRecord models' do
        lambda {
          MyModel.delay.long_class_method
        }.must_raise(NoMethodError)
      end

      it 'does not delay when disabled on ActiveModel mailers' do
        lambda {
          UserMailer.delay.greetings(1, 2)
        }.must_raise(NoMethodError)
      end
    end

    describe 'when using a different method base' do
      before do
        Sidekiq.delayed_extension_options = { 'base' => 'async' }
      end

      after do
        Sidekiq.delayed_extension_options = { 'base' => 'delay' }
      end

      it 'responds to the method on generic classes' do
        assert_equal 0, queue_size
        SomeClass.async.doit(Date.today)
        assert_equal 1, queue_size
      end

      it 'reponds to scheduling on generic classes' do
        assert_equal 0, Sidekiq.redis {|c| c.zcard('schedule') }
        SomeClass.async_for(5.days).doit(Date.today)
        SomeClass.async_until(1.day.from_now).doit(Date.today)
        assert_equal 2, Sidekiq.redis {|c| c.zcard('schedule') }
      end

      it 'responds to the method on module class methods' do
        assert_equal 0, queue_size
        SomeModule.async.doit(Date.today)
        assert_equal 1, queue_size
      end

      it 'responds to scheduling on module class methods' do
        assert_equal 0, Sidekiq.redis {|c| c.zcard('schedule') }
        SomeModule.async_for(5.days).doit(Date.today)
        SomeModule.async_until(1.day.from_now).doit(Date.today)
        assert_equal 2, Sidekiq.redis {|c| c.zcard('schedule') }
      end

      it 'responds to the method on ActiveRecord models' do
        assert_equal 0, queue_size
        MyModel.async.long_class_method
        assert_equal 1, queue_size
      end

      it 'responds to scheduling on ActiveRecord models' do
        assert_equal 0, Sidekiq.redis {|c| c.zcard('schedule') }
        MyModel.async_for(5.days).long_class_method
        MyModel.async_until(1.day.from_now).long_class_method
        assert_equal 2, Sidekiq.redis {|c| c.zcard('schedule') }
      end

      it 'responds to the method on ActiveModel mailers' do
        assert_equal 0, queue_size
        UserMailer.async.greetings(1, 2)
        assert_equal 1, queue_size
      end

      it 'responds to scheduling on ActiveModel mailers' do
        assert_equal 0, Sidekiq.redis {|c| c.zcard('schedule') }
        UserMailer.async_for(5.days).greetings(1, 2)
        UserMailer.async_until(1.day.from_now).greetings(1, 2)
        assert_equal 2, Sidekiq.redis {|c| c.zcard('schedule') }
      end
    end
  end

end
