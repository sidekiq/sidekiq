require 'helper'
require 'sidekiq'
require 'fileutils'
require 'active_record'
require 'action_mailer'
require 'sidekiq/extensions/action_mailer'
require 'sidekiq/extensions/active_record'
require 'sidekiq/rails'

require 'sidekiq/processor'

Sidekiq.hook_rails!

class TestExtensions < MiniTest::Unit::TestCase
  describe 'sidekiq extensions' do
    before do
      Sidekiq.redis = REDIS
      Sidekiq.redis {|c| c.flushdb }

      # overwrite db with blank one
      dir = File.join(File.dirname(__FILE__), 'db')
      
      old_db = File.join(dir, 'test.sqlite3')
      FileUtils.rm(old_db) if File.exists?(old_db)
      FileUtils.cp(File.join(dir, '_blank.sqlite3'), File.join(dir, 'test.sqlite3'))

      ActiveRecord::Base.establish_connection adapter: "sqlite3", database: File.join(File.dirname(__FILE__), "db/test.sqlite3")
    end

    class User < ActiveRecord::Base
      def self.long_class_method(arg)
        "done long_class_method #{arg}"
      end

      def long_instance_method(arg)
        "done long_instance_method #{arg}"
      end
    end

    def perform_last_job!(performer)
      msg = JSON.parse(Sidekiq.redis {|c| c.lrange "queue:default", 0, -1 }[0])
      performer.new.perform(*msg['args'])
    end

    it 'allows delayed execution of ActiveRecord class methods' do
      assert_equal [], Sidekiq::Client.registered_queues
      assert_equal 0, Sidekiq.redis {|c| c.llen('queue:default') }
      User.delay.long_class_method("with_argument")
      assert_equal ['default'], Sidekiq::Client.registered_queues
      assert_equal 1, Sidekiq.redis {|c| c.llen('queue:default') }

      assert_equal "done long_class_method with_argument", perform_last_job!(Sidekiq::Extensions::DelayedModel)
    end

    it 'allows delayed execution of ActiveRecord instance methods' do
      assert_equal [], Sidekiq::Client.registered_queues
      assert_equal 0, Sidekiq.redis {|c| c.llen('queue:default') }
      user = User.create!
      user.delay.long_instance_method("with_argument")
      assert_equal ['default'], Sidekiq::Client.registered_queues
      assert_equal 1, Sidekiq.redis {|c| c.llen('queue:default') }

      assert_equal "done long_instance_method with_argument", perform_last_job!(Sidekiq::Extensions::DelayedModel)
    end

    it 'allows delayed scheduling of AR class methods' do
      assert_equal 0, Sidekiq.redis {|c| c.zcard('schedule') }
      User.delay_for(5.days).long_class_method
      assert_equal 1, Sidekiq.redis {|c| c.zcard('schedule') }
    end

    it 'allows setting queue from options' do
      assert_equal [], Sidekiq::Client.registered_queues
      assert_equal 0, Sidekiq.redis {|c| c.llen('queue:custom_queue') }
      user = User.create!
      user.delay(queue: :custom_queue).long_instance_method("with_argument")
      assert_equal ['custom_queue'], Sidekiq::Client.registered_queues
      assert_equal 1, Sidekiq.redis {|c| c.llen('queue:custom_queue') }
    end

    ActionMailer::Base.perform_deliveries = false

    class UserMailer < ActionMailer::Base
      def greetings(email, name)
        mail from: "test@domain.com", to: email, subject: "Hello #{name}"
      end
    end

    it 'allows delayed delivery of ActionMailer mails' do
      assert_equal [], Sidekiq::Client.registered_queues
      assert_equal 0, Sidekiq.redis {|c| c.llen('queue:default') }
      UserMailer.delay.greetings("user@domain.com", "John Doe")
      assert_equal ['default'], Sidekiq::Client.registered_queues
      assert_equal 1, Sidekiq.redis {|c| c.llen('queue:default') }

      mail_message = perform_last_job!(Sidekiq::Extensions::DelayedMailer)
      assert_equal mail_message.to, ["user@domain.com"]
      assert_equal mail_message.subject, "Hello John Doe"
    end

    it 'allows delayed scheduling of AM mails' do
      assert_equal 0, Sidekiq.redis {|c| c.zcard('schedule') }
      UserMailer.delay_for(5.days).greetings(1, 2)
      assert_equal 1, Sidekiq.redis {|c| c.zcard('schedule') }
    end

    class SomeClass
      def self.doit(arg)
        ["done", arg]
      end
    end

    it 'allows delay of any ole class method' do
      today = Date.today
      SomeClass.delay.doit(Date.today)

      assert_equal ["done", today], perform_last_job!(Sidekiq::Extensions::DelayedClass)
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
