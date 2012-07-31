require 'helper'
require 'sidekiq/processor'

class TestProcessor < MiniTest::Unit::TestCase
  TestException = Class.new(StandardError)
  TEST_EXCEPTION = TestException.new("kerboom!")

  describe 'with mock setup' do
    before do
      $invokes = 0
      @boss = MiniTest::Mock.new
      @processor = ::Sidekiq::Processor.new(@boss)
      Celluloid.logger = nil
      Sidekiq.redis = REDIS
      @exception_handler = MiniTest::Mock.new
    end

    class MockWorker
      include Sidekiq::Worker
      def perform(args)
        raise TEST_EXCEPTION if args == 'boom'
        $invokes += 1
      end
    end

    it 'processes as expected' do
      msg = Sidekiq.dump_json({ 'class' => MockWorker.to_s, 'args' => ['myarg'] })
      @boss.expect(:processor_done!, nil, [@processor])
      @processor.process(msg, 'default')
      @boss.verify
      assert_equal 1, $invokes
    end

    it 'passes exceptions to ExceptionHandler' do
      msg = Sidekiq.dump_json({ 'class' => MockWorker.to_s, 'args' => ['boom'] })
      @processor.exception_handler = @exception_handler
      @exception_handler.expect(:handle,nil,[TEST_EXCEPTION,{"class"=>"TestProcessor::MockWorker", "args"=>["boom"]}])
      @processor.process(msg, 'default') rescue TestException
      @exception_handler.verify
      assert_equal 0, $invokes
    end

    it 're-raises exceptions after handling' do
      msg = Sidekiq.dump_json({ 'class' => MockWorker.to_s, 'args' => ['boom'] })
      re_raise = false

      begin
        @processor.process(msg, 'default')
      rescue TestException
        re_raise = true
      end

      assert re_raise, "does not re-raise exceptions after handling"
    end
  end
end
