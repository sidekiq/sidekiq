require 'helper'
require 'sidekiq'
require 'sidekiq/exception_handler'
require 'stringio'
require 'logger'

ExceptionHandlerTestException = Class.new(StandardError)
TEST_EXCEPTION = ExceptionHandlerTestException.new("Something didn't work!")

class Component
  include Sidekiq::ExceptionHandler

  def invoke_exception(args)
    raise TEST_EXCEPTION
  rescue ExceptionHandlerTestException => e
    handle_exception(e,args)
  end
end

class TestExceptionHandler < MiniTest::Unit::TestCase
  describe "with mock logger" do
    before do
      @old_logger = Sidekiq.logger
      @str_logger = StringIO.new
      Sidekiq.logger = Logger.new(@str_logger)
    end

    after do
      Sidekiq.logger = @old_logger
    end

    it "logs the exception to Sidekiq.logger" do
      Component.new.invoke_exception(:a => 1)
      @str_logger.rewind
      log = @str_logger.readlines
      assert_match /a=>1/, log[0], "didn't include the context"
      assert_match /Something didn't work!/, log[1], "didn't include the exception message"
      assert_match /test\/test_exception_handler.rb/, log[2], "didn't include the backtrace"
    end
  end

  describe "with fake Airbrake" do
    before do
      ::Airbrake = MiniTest::Mock.new
    end

    after do
      Object.send(:remove_const, "Airbrake") # HACK should probably inject Airbrake etc into this class in the future
    end

    it "notifies Airbrake" do
      ::Airbrake.expect(:notify_or_ignore,nil,[TEST_EXCEPTION,:parameters => { :a => 1 }])
      Component.new.invoke_exception(:a => 1)
      ::Airbrake.verify
    end
  end

  describe "with fake Honeybadger" do
    before do
      ::Honeybadger = MiniTest::Mock.new
    end

    after do
      Object.send(:remove_const, "Honeybadger") # HACK should probably inject Honeybadger etc into this class in the future
    end

    it "notifies Honeybadger" do
      ::Honeybadger.expect(:notify_or_ignore,nil,[TEST_EXCEPTION,:parameters => { :a => 1 }])
      Component.new.invoke_exception(:a => 1)
      ::Honeybadger.verify
    end
  end

  describe "with fake ExceptionNotifier" do
    before do
      ::ExceptionNotifier = Module.new
      ::ExceptionNotifier::Notifier = MiniTest::Mock.new
    end

    after do
      Object.send(:remove_const, "ExceptionNotifier")
    end

    it "notifies ExceptionNotifier" do
      mail = MiniTest::Mock.new
      mail.expect(:deliver,nil)
      ::ExceptionNotifier::Notifier.expect(:background_exception_notification,mail,[TEST_EXCEPTION, :data => { :message => { :b => 2 } }])
      Component.new.invoke_exception(:b => 2)
      ::ExceptionNotifier::Notifier.verify
      mail.verify
    end
  end

  describe "with fake Exceptional" do
    before do
      ::Exceptional = Class.new do

        def self.context(msg)
          @msg = msg
        end

        def self.check_context
          @msg
        end
      end

      ::Exceptional::Config = MiniTest::Mock.new
      ::Exceptional::Remote = MiniTest::Mock.new
      ::Exceptional::ExceptionData = MiniTest::Mock.new
    end

    after do
      Object.send(:remove_const, "Exceptional")
    end

    it "notifies Exceptional" do
      ::Exceptional::Config.expect(:should_send_to_api?,true)
      exception_data = Object.new
      ::Exceptional::Remote.expect(:error,nil,[exception_data])
      ::Exceptional::ExceptionData.expect(:new,exception_data,[TEST_EXCEPTION])
      Component.new.invoke_exception(:c => 3)
      assert_equal({:c => 3},::Exceptional.check_context,"did not record arguments properly")
      ::Exceptional::Config.verify
      ::Exceptional::Remote.verify
      ::Exceptional::ExceptionData.verify
    end
  end
end
