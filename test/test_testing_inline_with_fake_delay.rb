require 'helper'
require 'sidekiq'
require 'sidekiq/worker'
require 'active_record'
require 'action_mailer'
require 'sidekiq/rails'
require 'sidekiq/extensions/action_mailer'
require 'sidekiq/extensions/active_record'

Sidekiq.hook_rails!

class TestInlineWithFakeDelay < Sidekiq::Test
  describe 'sidekiq inline with fake delay testing' do
    class InlineError < RuntimeError ; end

    class InlineWorker
      include Sidekiq::Worker
      def perform(pass)
        raise InlineError unless pass
      end
    end

    class DelayedWorker
      include Sidekiq::Worker
      def perform(a, b)
        a + b
      end
    end

    before do
      require 'sidekiq/testing.rb'
      Sidekiq::Testing.inline_with_fake_delay!
      DelayedWorker.jobs.clear
    end

    after do
      Sidekiq::Testing.disable!
    end

    it 'stubs the async call for delayed workers' do
      assert_equal 0, DelayedWorker.jobs.size
      DelayedWorker.perform_in(10, 1, 2)
      assert_equal 1, DelayedWorker.jobs.size
      DelayedWorker.perform_at(10, 1, 2)
      assert_equal 2, DelayedWorker.jobs.size
    end

    it 'stubs the async call' do
      assert_equal 0, DelayedWorker.jobs.size
      DelayedWorker.perform_async(1, 2)
      assert_equal 0, DelayedWorker.jobs.size

      assert InlineWorker.perform_async(true)

      assert Sidekiq::Client.enqueue(InlineWorker, true)
      assert_equal 0, InlineWorker.jobs.size

      assert_raises InlineError do
        Sidekiq::Client.enqueue(InlineWorker, false)
      end
    end
  end
end
