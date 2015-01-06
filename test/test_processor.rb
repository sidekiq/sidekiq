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

    describe 'stats' do
      before do
        Sidekiq.redis {|c| c.flushdb }
      end

      def with_expire(time)
        begin
          old = Sidekiq::Processor::STATS_TIMEOUT
          silence_warnings { Sidekiq::Processor.const_set(:STATS_TIMEOUT, time) }
          yield
        ensure
          silence_warnings { Sidekiq::Processor.const_set(:STATS_TIMEOUT, old) }
        end
      end

      describe 'when successful' do
        let(:processed_today_key) { "stat:processed:#{Time.now.utc.to_date}" }

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
          successful_job
          assert_equal 1, Sidekiq::Stats.new.processed
        end

        it 'expires processed stat' do
          successful_job
          assert_equal Sidekiq::Processor::STATS_TIMEOUT, Sidekiq.redis { |conn| conn.ttl(processed_today_key) }
        end

        it 'increments date processed stat' do
          successful_job
          assert_equal 1, Sidekiq.redis { |conn| conn.get(processed_today_key) }.to_i
        end
      end

      describe 'when failed' do
        let(:failed_today_key) { "stat:failed:#{Time.now.utc.to_date}" }

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
          failed_job
          assert_equal 1, Sidekiq::Stats.new.failed
        end

        it 'increments date failed stat' do
          failed_job
          assert_equal 1, Sidekiq.redis { |conn| conn.get(failed_today_key) }.to_i
        end

        it 'expires failed stat' do
          failed_job
          assert_equal Sidekiq::Processor::STATS_TIMEOUT, Sidekiq.redis { |conn| conn.ttl(failed_today_key) }
        end
      end
    end
  end
end
