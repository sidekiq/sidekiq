# frozen_string_literal: true

require_relative "helper"
require "sidekiq/component"
require "stringio"
require "logger"

ExceptionHandlerTestException = Class.new(StandardError)
TEST_EXCEPTION = ExceptionHandlerTestException.new("Something didn't work!")

class Thing
  include Sidekiq::Component
  attr_reader :config

  def initialize(config)
    @config = config
  end

  def invoke_exception(args)
    raise TEST_EXCEPTION
  rescue ExceptionHandlerTestException => e
    handle_exception(e, args)
  end
end

describe Sidekiq::Component do
  describe "with mock logger" do
    before do
      @config = reset!
    end

    it "logs the exception to Sidekiq.logger" do
      output = capture_logging(@config) do
        Thing.new(@config).invoke_exception(a: 1)
      end
      assert_match(/"a":1/, output, "didn't include the context")
      assert_match(/Something didn't work!/, output, "didn't include the exception message")
      assert_match(/test\/exception_handler_test.rb/, output, "didn't include the backtrace")
    end

    describe "when the exception does not have a backtrace" do
      it "does not fail" do
        exception = ExceptionHandlerTestException.new
        assert_nil exception.backtrace

        Thing.new(@config).handle_exception exception
      end
    end
  end
end
