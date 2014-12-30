require_relative 'helper'
require 'sidekiq'
require 'sidekiq/worker'
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
        require 'sidekiq/testing.rb'
      end

      after do
        Sidekiq::Testing.disable!
      end

      it 'enables fake testing' do
        Sidekiq::Testing.fake!
        assert_equal true, Sidekiq::Testing.enabled?
        assert_equal true, Sidekiq::Testing.fake?
      end

      it 'enables fake testing in a block' do
        Sidekiq::Testing.disable!
        assert_equal true, Sidekiq::Testing.disabled?

        Sidekiq::Testing.fake! do
          assert_equal true, Sidekiq::Testing.enabled?
          assert_equal true, Sidekiq::Testing.fake?
        end

        assert_equal false, Sidekiq::Testing.enabled?
        assert_equal false, Sidekiq::Testing.fake?
      end

      it 'disables testing in a block' do
        Sidekiq::Testing.fake!

        Sidekiq::Testing.disable! do
          assert_equal true, Sidekiq::Testing.disabled?
        end

        assert_equal true, Sidekiq::Testing.enabled?
      end
    end

    describe 'require/load sidekiq/testing/inline.rb' do
      before do
        require 'sidekiq/testing/inline.rb'
      end

      after do
        Sidekiq::Testing.disable!
      end

      it 'enables inline testing' do
        Sidekiq::Testing.inline!
        assert_equal true, Sidekiq::Testing.enabled?
        assert_equal true, Sidekiq::Testing.inline?
      end

      it 'enables inline testing in a block' do
        Sidekiq::Testing.disable!
        assert_equal true, Sidekiq::Testing.disabled?

        Sidekiq::Testing.inline! do
          assert_equal true, Sidekiq::Testing.enabled?
          assert_equal true, Sidekiq::Testing.inline?
        end

        assert_equal false, Sidekiq::Testing.enabled?
        assert_equal false, Sidekiq::Testing.inline?
      end
    end
  end
end
