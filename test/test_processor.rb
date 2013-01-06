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
    end

    class MockWorker
      include Sidekiq::Worker
      def perform(args)
        raise TEST_EXCEPTION if args == 'boom'
        args.pop if args.is_a? Array
        $invokes += 1
      end
    end

    def work(msg, queue='queue:default')
      Sidekiq::BasicFetch::UnitOfWork.new(queue, msg)
    end

    it 'processes as expected' do
      msg = Sidekiq.dump_json({ 'class' => MockWorker.to_s, 'args' => ['myarg'] })
      actor = MiniTest::Mock.new
      actor.expect(:processor_done, nil, [@processor])
      @boss.expect(:async, actor, [])
      @processor.process(work(msg))
      @boss.verify
      assert_equal 1, $invokes
    end

    it 'passes exceptions to ExceptionHandler' do
      msg = Sidekiq.dump_json({ 'class' => MockWorker.to_s, 'args' => ['boom'] })
      begin
        @processor.process(work(msg))
        flunk "Expected #process to raise exception"
      rescue TestException
      end

      assert_equal 0, $invokes
    end

    it 're-raises exceptions after handling' do
      msg = Sidekiq.dump_json({ 'class' => MockWorker.to_s, 'args' => ['boom'] })
      re_raise = false

      begin
        @processor.process(work(msg))
      rescue TestException
        re_raise = true
      end

      assert re_raise, "does not re-raise exceptions after handling"
    end

    it 'does not modify original arguments' do
      msg = { 'class' => MockWorker.to_s, 'args' => [['myarg']] }
      msgstr = Sidekiq.dump_json(msg)
      processor = ::Sidekiq::Processor.new(@boss)
      actor = MiniTest::Mock.new
      actor.expect(:processor_done, nil, [processor])
      @boss.expect(:async, actor, [])
      processor.process(work(msgstr))
      assert_equal [['myarg']], msg['args']
    end

    describe 'stats' do
      before do
        Sidekiq.redis {|c| c.flushdb }
      end

      describe 'when successful' do
        def successful_job
          msg = Sidekiq.dump_json({ 'class' => MockWorker.to_s, 'args' => ['myarg'] })
          actor = MiniTest::Mock.new
          actor.expect(:processor_done, nil, [@processor])
          @boss.expect(:async, actor, [])
          @processor.process(work(msg))
        end

        it 'increments processed stat' do
          successful_job
          assert_equal 1, Sidekiq::Stats.new.processed
        end

        it 'increments date processed stat' do
          Time.stub(:now, Time.parse("2012-12-25 1:00:00 -0500")) do
            successful_job
            date_processed = Sidekiq.redis { |conn| conn.get("stat:processed:2012-12-25") }.to_i
            assert_equal 1, date_processed
          end
        end
      end

      describe 'when failed' do
        def failed_job
          msg = Sidekiq.dump_json({ 'class' => MockWorker.to_s, 'args' => ['boom'] })
          begin
            @processor.process(work(msg))
          rescue TestException
          end
        end

        it 'increments failed stat' do
          failed_job
          assert_equal 1, Sidekiq::Stats.new.failed
        end

        it 'increments date failed stat' do
          Time.stub(:now, Time.parse("2012-12-25 1:00:00 -0500")) do
            failed_job
            date_failed = Sidekiq.redis { |conn| conn.get("stat:failed:2012-12-25") }.to_i
            assert_equal 1, date_failed
          end
        end
      end

    end
  end
end
