require_relative 'helper'
require 'sidekiq'
require 'active_record'
require 'action_mailer'
require 'sidekiq/rails'
require 'sidekiq/extensions/action_mailer'
require 'sidekiq/extensions/active_record'

Sidekiq.hook_rails!

class TestInline < Sidekiq::Test
  describe 'sidekiq inline testing' do
    class InlineError < RuntimeError; end
    class ParameterIsNotString < RuntimeError; end

    class InlineJob
      include Sidekiq::Job
      def perform(pass)
        raise ArgumentError, "no jid" unless jid
        raise InlineError unless pass
      end
    end

    class InlineJobWithTimeParam
      include Sidekiq::Job
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
      require 'sidekiq/testing/inline.rb'
      Sidekiq::Testing.inline!
    end

    after do
      Sidekiq::Testing.disable!
    end

    it 'stubs the async call when in testing mode' do
      assert InlineJob.perform_async(true)

      assert_raises InlineError do
        InlineJob.perform_async(false)
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
      assert Sidekiq::Client.enqueue(InlineJob, true)

      assert_raises InlineError do
        Sidekiq::Client.enqueue(InlineJob, false)
      end
    end

    it 'stubs the push_bulk call when in testing mode' do
      assert Sidekiq::Client.push_bulk({'class' => InlineJob, 'args' => [[true], [true]]})

      assert_raises InlineError do
        Sidekiq::Client.push_bulk({'class' => InlineJob, 'args' => [[true], [false]]})
      end
    end

    it 'should relay parameters through json' do
      assert Sidekiq::Client.enqueue(InlineJobWithTimeParam, Time.now)
    end
  end
end
