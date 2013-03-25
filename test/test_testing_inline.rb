require 'helper'
require 'sidekiq'
require 'sidekiq/worker'
require 'active_record'
require 'action_mailer'
require 'sidekiq/rails'
require 'sidekiq/extensions/action_mailer'
require 'sidekiq/extensions/active_record'

Sidekiq.hook_rails!

class TestInline < MiniTest::Unit::TestCase
  describe 'sidekiq inline testing' do
    class InlineError < RuntimeError; end
    class ParameterIsNotString < RuntimeError; end

    class InlineWorker
      include Sidekiq::Worker
      def perform(pass)
        raise InlineError unless pass
      end
    end

    class InlineWorkerWithTimeParam
      include Sidekiq::Worker
      def perform(time)
        raise ParameterIsNotString unless time.is_a?(String) || time.is_a?(Numeric)
      end
    end

    class InlineFooMailer < ActionMailer::Base
      def bar(str)
        raise InlineError
      end
    end

    class InlineFooModel < ActiveRecord::Base
      def self.bar(str)
        raise InlineError
      end
    end

    before do
      load 'sidekiq/testing/inline.rb'
    end

    after do
      Sidekiq::Client.singleton_class.class_eval do
        remove_method :raw_push
        alias_method :raw_push, :raw_push_old
        remove_method :raw_push_old
      end
    end

    it 'stubs the async call when in testing mode' do
      assert InlineWorker.perform_async(true)

      assert_raises InlineError do
        InlineWorker.perform_async(false)
      end
    end

    it 'stubs the delay call on mailers' do
      assert_raises InlineError do
        InlineFooMailer.delay.bar('three')
      end
    end

    it 'stubs the delay call on models' do
      assert_raises InlineError do
        InlineFooModel.delay.bar('three')
      end
    end

    it 'stubs the enqueue call when in testing mode' do
      assert Sidekiq::Client.enqueue(InlineWorker, true)

      assert_raises InlineError do
        Sidekiq::Client.enqueue(InlineWorker, false)
      end
    end

    it 'stubs the push_bulk call when in testing mode' do
      assert Sidekiq::Client.push_bulk({'class' => InlineWorker, 'args' => [[true], [true]]})

      assert_raises InlineError do
        Sidekiq::Client.push_bulk({'class' => InlineWorker, 'args' => [[true], [false]]})
      end
    end

    it 'should relay parameters through json' do
      assert Sidekiq::Client.enqueue(InlineWorkerWithTimeParam, Time.now)
    end
  end
end
