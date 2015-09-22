require_relative 'helper'

require 'active_record'
require 'action_mailer'
require 'sidekiq/rails'
require 'sidekiq/extensions/action_mailer'
require 'sidekiq/extensions/active_record'

Sidekiq.hook_rails!

class TestTesting < Sidekiq::Test
  describe 'sidekiq testing' do
    describe 'require/load sidekiq/testing.rb' do
      before do
        require 'sidekiq/testing'
      end

      after do
        Sidekiq::Testing.disable!
      end

      it 'enables fake testing' do
        Sidekiq::Testing.fake!
        assert Sidekiq::Testing.enabled?
        assert Sidekiq::Testing.fake?
        refute Sidekiq::Testing.inline?
      end

      it 'enables fake testing in a block' do
        Sidekiq::Testing.disable!
        assert Sidekiq::Testing.disabled?
        refute Sidekiq::Testing.fake?

        Sidekiq::Testing.fake! do
          assert Sidekiq::Testing.enabled?
          assert Sidekiq::Testing.fake?
          refute Sidekiq::Testing.inline?
        end

        refute Sidekiq::Testing.enabled?
        refute Sidekiq::Testing.fake?
      end

      it 'disables testing in a block' do
        Sidekiq::Testing.fake!
        assert Sidekiq::Testing.fake?

        Sidekiq::Testing.disable! do
          refute Sidekiq::Testing.fake?
          assert Sidekiq::Testing.disabled?
        end

        assert Sidekiq::Testing.fake?
        assert Sidekiq::Testing.enabled?
      end
    end

    describe 'require/load sidekiq/testing/inline.rb' do
      before do
        require 'sidekiq/testing/inline'
      end

      after do
        Sidekiq::Testing.disable!
      end

      it 'enables inline testing' do
        Sidekiq::Testing.inline!
        assert Sidekiq::Testing.enabled?
        assert Sidekiq::Testing.inline?
        refute Sidekiq::Testing.fake?
      end

      it 'enables inline testing in a block' do
        Sidekiq::Testing.disable!
        assert Sidekiq::Testing.disabled?
        refute Sidekiq::Testing.fake?

        Sidekiq::Testing.inline! do
          assert Sidekiq::Testing.enabled?
          assert Sidekiq::Testing.inline?
        end

        refute Sidekiq::Testing.enabled?
        refute Sidekiq::Testing.inline?
        refute Sidekiq::Testing.fake?
      end
    end
  end

  describe 'with middleware' do
    before do
      require 'sidekiq/testing'
    end

    after do
      Sidekiq::Testing.disable!
    end

    class AttributeWorker
      include Sidekiq::Worker
      class_attribute :count
      self.count = 0
      attr_accessor :foo

      def perform
        self.class.count += 1 if foo == :bar
      end
    end

    class AttributeMiddleware
      def call(worker, msg, queue)
        worker.foo = :bar if worker.respond_to?(:foo=)
        yield
      end
    end

    it 'wraps the inlined worker with middleware' do
      Sidekiq::Testing.server_middleware do |chain|
        chain.add AttributeMiddleware
      end

      begin
        Sidekiq::Testing.fake! do
          AttributeWorker.perform_async
          assert_equal 0, AttributeWorker.count
        end

        AttributeWorker.perform_one
        assert_equal 1, AttributeWorker.count

        Sidekiq::Testing.inline! do
          AttributeWorker.perform_async
          assert_equal 2, AttributeWorker.count
        end
      ensure
        Sidekiq::Testing.server_middleware.clear
      end
    end
  end

end
