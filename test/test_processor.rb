require_relative 'helper'
require 'sidekiq/processor'

class TestProcessor < Sidekiq::Test
  TestException = Class.new(StandardError)
  TEST_EXCEPTION = TestException.new("kerboom!")

  describe 'with mock setup' do
    before do
      $invokes = 0
      @boss = Minitest::Mock.new
      @processor = ::Sidekiq::Processor.new(@boss)
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
      actor = Minitest::Mock.new
      actor.expect(:processor_done, nil, [@processor])
      actor.expect(:real_thread, nil, [nil, Thread])
      @boss.expect(:async, actor, [])
      @boss.expect(:async, actor, [])
      @processor.process(work(msg))
      @boss.verify
      assert_equal 1, $invokes
    end

    it 'executes a worker as expected' do
      worker = Minitest::Mock.new
      worker.expect(:perform, nil, [1, 2, 3])
      @processor.execute_job(worker, [1, 2, 3])
    end

    it 'passes exceptions to ExceptionHandler' do
      actor = Minitest::Mock.new
      actor.expect(:real_thread, nil, [nil, Thread])
      @boss.expect(:async, actor, [])
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
      actor = Minitest::Mock.new
      actor.expect(:real_thread, nil, [nil, Thread])
      @boss.expect(:async, actor, [])

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
      actor = Minitest::Mock.new
      actor.expect(:processor_done, nil, [processor])
      actor.expect(:real_thread, nil, [nil, Thread])
      @boss.expect(:async, actor, [])
      @boss.expect(:async, actor, [])
      processor.process(work(msgstr))
      assert_equal [['myarg']], msg['args']
    end

    describe 'acknowledgement' do
      class ExceptionRaisingMiddleware
        def initialize(raise_before_yield, raise_after_yield, skip)
          @raise_before_yield = raise_before_yield
          @raise_after_yield = raise_after_yield
          @skip = skip
        end

        def call(worker, item, queue)
          raise TEST_EXCEPTION if @raise_before_yield
          yield unless @skip
          raise TEST_EXCEPTION if @raise_after_yield
        end
      end

      let(:raise_before_yield) { false }
      let(:raise_after_yield) { false }
      let(:skip_job) { false }
      let(:worker_args) { ['myarg'] }
      let(:work) { MiniTest::Mock.new }
      let(:actor) { Minitest::Mock.new }

      before do
        work.expect(:queue_name, 'queues:default')
        work.expect(:message, Sidekiq.dump_json({ 'class' => MockWorker.to_s, 'args' => worker_args }))
        Sidekiq.server_middleware do |chain|
          chain.prepend ExceptionRaisingMiddleware, raise_before_yield, raise_after_yield, skip_job
        end

        actor.expect(:real_thread, nil, [nil, Thread])
        @boss.expect(:async, actor, [])
      end

      after do
        Sidekiq.server_middleware do |chain|
          chain.remove ExceptionRaisingMiddleware
        end
        work.verify
      end

      describe 'middleware throws an exception before processing the work' do
        let(:raise_before_yield) { true }

        it 'does not ack' do
          begin
            @processor.process(work)
            flunk "Expected #process to raise exception"
          rescue TestException
          end
        end
      end

      describe 'middleware throws an exception after processing the work' do
        let(:raise_after_yield) { true }

        it 'acks the job' do
          work.expect(:acknowledge, nil)
          begin
            @processor.process(work)
            flunk "Expected #process to raise exception"
          rescue TestException
          end
        end
      end

      describe 'middleware decides to skip work' do
        let(:skip_job) { true }

        it 'acks the job' do
          work.expect(:acknowledge, nil)
          @boss.expect(:async, actor, [])
          actor.expect(:processor_done, nil, [@processor])
          @processor.process(work)
        end
      end

      describe 'worker raises an exception' do
        let(:worker_args) { ['boom'] }

        it 'acks the job' do
          work.expect(:acknowledge, nil)
          begin
            @processor.process(work)
            flunk "Expected #process to raise exception"
          rescue TestException
          end
        end
      end

      describe 'everything goes well' do
        it 'acks the job' do
          work.expect(:acknowledge, nil)
          @boss.expect(:async, actor, [])
          actor.expect(:processor_done, nil, [@processor])
          @processor.process(work)
        end
      end
    end

    describe 'stats' do
      before do
        Sidekiq.redis {|c| c.flushdb }
      end

      describe 'when successful' do
        let(:processed_today_key) { "stat:processed:#{Time.now.utc.strftime("%Y-%m-%d")}" }

        def successful_job
          msg = Sidekiq.dump_json({ 'class' => MockWorker.to_s, 'args' => ['myarg'] })
          actor = Minitest::Mock.new
          actor.expect(:real_thread, nil, [nil, Thread])
          actor.expect(:processor_done, nil, [@processor])
          @boss.expect(:async, actor, [])
          @boss.expect(:async, actor, [])
          @processor.process(work(msg))
        end

        it 'increments processed stat' do
          assert_equal 0, Sidekiq::Stats.new.processed
          successful_job
          assert_equal 1, Sidekiq::Stats.new.processed
          assert_equal Sidekiq::Processor::STATS_TIMEOUT, Sidekiq.redis { |conn| conn.ttl(processed_today_key) }
        end
      end

      describe 'when failed' do
        let(:failed_today_key) { "stat:failed:#{Time.now.utc.strftime("%Y-%m-%d")}" }

        def failed_job
          actor = Minitest::Mock.new
          actor.expect(:real_thread, nil, [nil, Thread])
          @boss.expect(:async, actor, [])
          msg = Sidekiq.dump_json({ 'class' => MockWorker.to_s, 'args' => ['boom'] })
          begin
            @processor.process(work(msg))
          rescue TestException
          end
        end

        it 'increments failed stat' do
          assert_equal 0, Sidekiq::Stats.new.failed
          failed_job
          assert_equal 1, Sidekiq::Stats.new.failed
          assert_equal Sidekiq::Processor::STATS_TIMEOUT, Sidekiq.redis { |conn| conn.ttl(failed_today_key) }
        end
      end
    end
  end
end
