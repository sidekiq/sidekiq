# frozen_string_literal: true
require_relative 'helper'
require 'sidekiq/fetch'
require 'sidekiq/cli'
require 'sidekiq/processor'

class TestProcessor < Minitest::Test
  TestException = Class.new(StandardError)
  TEST_EXCEPTION = TestException.new("kerboom!")

  describe 'processor' do
    before do
      $invokes = 0
      @mgr = Minitest::Mock.new
      @mgr.expect(:options, {:queues => ['default']})
      @mgr.expect(:options, {:queues => ['default']})
      @mgr.expect(:options, {:queues => ['default']})
      @processor = ::Sidekiq::Processor.new(@mgr)
    end

    class MockWorker
      include Sidekiq::Worker
      def perform(args)
        raise TEST_EXCEPTION if args.to_s == 'boom'
        args.pop if args.is_a? Array
        $invokes += 1
      end
    end

    def work(msg, queue='queue:default')
      Sidekiq::BasicFetch::UnitOfWork.new(queue, msg)
    end

    it 'processes as expected' do
      msg = Sidekiq.dump_json({ 'class' => MockWorker.to_s, 'args' => ['myarg'] })
      @processor.process(work(msg))
      assert_equal 1, $invokes
    end

    it 'executes a worker as expected' do
      worker = Minitest::Mock.new
      worker.expect(:perform, nil, [1, 2, 3])
      @processor.execute_job(worker, [1, 2, 3])
    end

    it 're-raises exceptions after handling' do
      msg = Sidekiq.dump_json({ 'class' => MockWorker.to_s, 'args' => ['boom'] })
      re_raise = false

      begin
        @processor.process(work(msg))
        flunk "Expected exception"
      rescue TestException
        re_raise = true
      end

      assert_equal 0, $invokes
      assert re_raise, "does not re-raise exceptions after handling"
    end

    it 'does not modify original arguments' do
      msg = { 'class' => MockWorker.to_s, 'args' => [['myarg']] }
      msgstr = Sidekiq.dump_json(msg)
      @mgr.expect(:processor_done, nil, [@processor])
      @processor.process(work(msgstr))
      assert_equal [['myarg']], msg['args']
    end

    describe 'exception handling' do
      let(:errors) { [] }
      let(:error_handler) do
        proc do |exception, context|
          errors << { exception: exception, context: context }
        end
      end

      before do
        Sidekiq.error_handlers << error_handler
      end

      after do
        Sidekiq.error_handlers.pop
      end

      it 'handles invalid JSON' do
        ds = Sidekiq::DeadSet.new
        ds.clear
        job_hash = { 'class' => MockWorker.to_s, 'args' => ['boom'] }
        msg = Sidekiq.dump_json(job_hash)
        job = work(msg[0...-2])
        ds = Sidekiq::DeadSet.new
        assert_equal 0, ds.size
        begin
          @processor.instance_variable_set(:'@job', job)
          @processor.process(job)
        rescue JSON::ParserError
        end
        assert_equal 1, ds.size
      end

      it 'handles exceptions raised by the job' do
        job_hash = { 'class' => MockWorker.to_s, 'args' => ['boom'], 'jid' => '123987123' }
        msg = Sidekiq.dump_json(job_hash)
        job = work(msg)
        begin
          @processor.instance_variable_set(:'@job', job)
          @processor.process(job)
        rescue TestException
        end
        assert_equal 1, errors.count
        assert_instance_of TestException, errors.first[:exception]
        assert_equal msg, errors.first[:context][:jobstr]
        assert_equal job_hash['jid'], errors.first[:context][:job]['jid']
      end

      it 'handles exceptions raised by the reloader' do
        job_hash = { 'class' => MockWorker.to_s, 'args' => ['boom'] }
        msg = Sidekiq.dump_json(job_hash)
        @processor.instance_variable_set(:'@reloader', proc { raise TEST_EXCEPTION })
        job = work(msg)
        begin
          @processor.instance_variable_set(:'@job', job)
          @processor.process(job)
        rescue TestException
        end
        assert_equal 1, errors.count
        assert_instance_of TestException, errors.first[:exception]
        assert_equal msg, errors.first[:context][:jobstr]
        assert_equal job_hash, errors.first[:context][:job]
      end

      it 'handles exceptions raised during fetch' do
        fetch_stub = lambda { raise StandardError, "fetch exception" }
        # swallow logging because actually care about the added exception handler
        capture_logging do
          @processor.instance_variable_get('@strategy').stub(:retrieve_work, fetch_stub) do
            @processor.process_one
          end
        end

        assert_instance_of StandardError, errors.last[:exception]
      end
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

      before do
        work.expect(:queue_name, 'queue:default')
        work.expect(:job, Sidekiq.dump_json({ 'class' => MockWorker.to_s, 'args' => worker_args }))
        Sidekiq.server_middleware do |chain|
          chain.prepend ExceptionRaisingMiddleware, raise_before_yield, raise_after_yield, skip_job
        end
      end

      after do
        Sidekiq.server_middleware do |chain|
          chain.remove ExceptionRaisingMiddleware
        end
        work.verify
      end

      describe 'middleware throws an exception before processing the work' do
        let(:raise_before_yield) { true }

        it 'acks the job' do
          work.expect(:acknowledge, nil)
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
          @mgr.expect(:processor_done, nil, [@processor])
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
          @mgr.expect(:processor_done, nil, [@processor])
          @processor.process(work)
        end
      end
    end

    describe 'retry' do
      class ArgsMutatingServerMiddleware
        def call(worker, item, queue)
          item['args'] = item['args'].map do |arg|
            arg.to_sym if arg.is_a?(String)
          end
          yield
        end
      end

      class ArgsMutatingClientMiddleware
        def call(worker, item, queue, redis_pool)
          item['args'] = item['args'].map do |arg|
            arg.to_s if arg.is_a?(Symbol)
          end
          yield
        end
      end

      before do
        Sidekiq.server_middleware do |chain|
          chain.prepend ArgsMutatingServerMiddleware
        end
        Sidekiq.client_middleware do |chain|
          chain.prepend ArgsMutatingClientMiddleware
        end
      end

      after do
        Sidekiq.server_middleware do |chain|
          chain.remove ArgsMutatingServerMiddleware
        end
        Sidekiq.client_middleware do |chain|
          chain.remove ArgsMutatingClientMiddleware
        end
      end

      describe 'middleware mutates the job args and then fails' do
        it 'requeues with original arguments' do
          job_data = { 'class' => MockWorker.to_s, 'args' => ['boom'] }

          retry_stub_called = false
          retry_stub = lambda { |worker, msg, queue, exception|
            retry_stub_called = true
            assert_equal 'boom', msg['args'].first
          }

          @processor.instance_variable_get('@retrier').stub(:attempt_retry, retry_stub) do
            msg = Sidekiq.dump_json(job_data)
            begin
              @processor.process(work(msg))
              flunk "Expected exception"
            rescue TestException
            end
          end

          assert retry_stub_called
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
          @mgr.expect(:processor_done, nil, [@processor])
          @processor.process(work(msg))
        end

        it 'increments processed stat' do
          Sidekiq::Processor::PROCESSED.reset
          successful_job
          assert_equal 1, Sidekiq::Processor::PROCESSED.reset
        end
      end

      describe 'when failed' do
        let(:failed_today_key) { "stat:failed:#{Time.now.utc.strftime("%Y-%m-%d")}" }

        def failed_job
          msg = Sidekiq.dump_json({ 'class' => MockWorker.to_s, 'args' => ['boom'] })
          begin
            @processor.process(work(msg))
          rescue TestException
          end
        end

        it 'increments failed stat' do
          Sidekiq::Processor::FAILURE.reset
          failed_job
          assert_equal 1, Sidekiq::Processor::FAILURE.reset
        end
      end
    end

    describe 'custom job logger class' do
      class CustomJobLogger < Sidekiq::JobLogger
        def call(item, queue)
          yield
        rescue Exception
          raise
        end
      end

      before do
        @mgr = Minitest::Mock.new
        @mgr.expect(:options, {:queues => ['default'], job_logger: CustomJobLogger})
        @mgr.expect(:options, {:queues => ['default'], job_logger: CustomJobLogger})
        @mgr.expect(:options, {:queues => ['default'], job_logger: CustomJobLogger})
        @processor = ::Sidekiq::Processor.new(@mgr)
      end

      it 'is called instead default Sidekiq::JobLogger' do
        msg = Sidekiq.dump_json({ 'class' => MockWorker.to_s, 'args' => ['myarg'] })
        @processor.process(work(msg))
        assert_equal 1, $invokes
        @mgr.verify
      end
    end
  end
end
