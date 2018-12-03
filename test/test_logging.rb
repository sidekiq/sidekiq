# frozen_string_literal: true
require_relative 'helper'
require 'sidekiq/logging'

class TestLogging < Minitest::Test
  describe Sidekiq::Logging do
    describe "#with_context" do
      def ctx
        Sidekiq::Logging.logger.formatter.context
      end

      it "has no context by default" do
        assert_nil ctx
      end

      it "can add a context" do
        Sidekiq::Logging.with_context "xx" do
          assert_equal " xx", ctx
        end
        assert_nil ctx
      end

      it "can use multiple contexts" do
        Sidekiq::Logging.with_context "xx" do
          assert_equal " xx", ctx
          Sidekiq::Logging.with_context "yy" do
            assert_equal " xx yy", ctx
          end
          assert_equal " xx", ctx
        end
        assert_nil ctx
      end
    end
  end
end
