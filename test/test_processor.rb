# frozen_string_literal: true

require_relative "helper"
require "sidekiq/fetch"
require "sidekiq/cli"
require "sidekiq/processor"

describe Sidekiq::Processor do
  TestProcessorException = Class.new(StandardError)
  TEST_PROC_EXCEPTION = TestProcessorException.new("kerboom!")

  before do
    $invokes = 0
    @config = Sidekiq
    @config[:fetch] = Sidekiq::BasicFetch.new(@config)
    @processor = ::Sidekiq::Processor.new(@config) { |*args| }
  end

  class MockWorker
    include Sidekiq::Worker
    def perform(args)
      raise TEST_PROC_EXCEPTION if args.to_s == "boom"
      args.pop if args.is_a? Array
      $invokes += 1
    end
  end

  def work(msg, queue = "queue:default")
    Sidekiq::BasicFetch::UnitOfWork.new(queue, msg)
  end

  it "processes as expected" do
    msg = Sidekiq.dump_json({"class" => MockWorker.to_s, "args" => ["myarg"]})
    @processor.process(work(msg))
    assert_equal 1, $invokes
  end

  it "executes a worker as expected" do
    worker = Minitest::Mock.new
    worker.expect(:perform, nil, [1, 2, 3])
    @processor.execute_job(worker, [1, 2, 3])
  end

  it "re-raises exceptions after handling" do
    msg = Sidekiq.dump_json({"class" => MockWorker.to_s, "args" => ["boom"]})
    re_raise = false

    begin
      @processor.process(work(msg))
      flunk "Expected exception"
    rescue TestProcessorException
      re_raise = true
    end

    assert_equal 0, $invokes
    assert re_raise, "does not re-raise exceptions after handling"
  end

  it "does not modify original arguments" do
    msg = {"class" => MockWorker.to_s, "args" => [["myarg"]]}
    msgstr = Sidekiq.dump_json(msg)
    @processor.process(work(msgstr))
    assert_equal [["myarg"]], msg["args"]
  end

  describe "exception handling" do
    let(:errors) { [] }
    let(:error_handler) do
      proc do |exception, context|
        errors << {exception: exception, context: context}
      end
    end

    before do
      Sidekiq.error_handlers << error_handler
    end

    after do
      Sidekiq.error_handlers.pop
    end

    it "handles invalid JSON" do
      ds = Sidekiq::DeadSet.new
      ds.clear
      job_hash = {"class" => MockWorker.to_s, "args" => ["boom"]}
      msg = Sidekiq.dump_json(job_hash)
      job = work(msg[0...-2])
      ds = Sidekiq::DeadSet.new
      assert_equal 0, ds.size
      begin
        @processor.instance_variable_set(:@job, job)
        @processor.process(job)
      rescue JSON::ParserError
      end
      assert_equal 1, ds.size
    end

    it "handles exceptions raised by the job" do
      job_hash = {"class" => MockWorker.to_s, "args" => ["boom"], "jid" => "123987123"}
      msg = Sidekiq.dump_json(job_hash)
      job = work(msg)
      begin
        @processor.instance_variable_set(:@job, job)
        @processor.process(job)
      rescue TestProcessorException
      end
      assert_equal 1, errors.count
      assert_instance_of TestProcessorException, errors.first[:exception]
      assert_equal msg, errors.first[:context][:jobstr]
      assert_equal job_hash["jid"], errors.first[:context][:job]["jid"]
    end

    it "handles exceptions raised by the reloader" do
      job_hash = {"class" => MockWorker.to_s, "args" => ["boom"]}
      msg = Sidekiq.dump_json(job_hash)
      @processor.instance_variable_set(:@reloader, proc { raise TEST_PROC_EXCEPTION })
      job = work(msg)
      begin
        @processor.instance_variable_set(:@job, job)
        @processor.process(job)
      rescue TestProcessorException
      end
      assert_equal 1, errors.count
      assert_instance_of TestProcessorException, errors.first[:exception]
      assert_equal msg, errors.first[:context][:jobstr]
      assert_equal job_hash, errors.first[:context][:job]
    end

    it "handles exceptions raised during fetch" do
      fetch_stub = lambda { raise StandardError, "fetch exception" }
      # swallow logging because actually care about the added exception handler
      capture_logging do
        @processor.instance_variable_get(:@strategy).stub(:retrieve_work, fetch_stub) do
          @processor.process_one
        end
      end

      assert_instance_of StandardError, errors.last[:exception]
    end
  end

  describe "acknowledgement" do
    class ExceptionRaisingMiddleware
      def initialize(raise_before_yield, raise_after_yield, skip)
        @raise_before_yield = raise_before_yield
        @raise_after_yield = raise_after_yield
        @skip = skip
      end

      def call(worker, item, queue)
        raise TEST_PROC_EXCEPTION if @raise_before_yield
        yield unless @skip
        raise TEST_PROC_EXCEPTION if @raise_after_yield
      end
    end

    let(:raise_before_yield) { false }
    let(:raise_after_yield) { false }
    let(:skip_job) { false }
    let(:worker_args) { ["myarg"] }
    let(:work) { MiniTest::Mock.new }

    before do
      work.expect(:queue_name, "queue:default")
      work.expect(:job, Sidekiq.dump_json({"class" => MockWorker.to_s, "args" => worker_args}))
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

    describe "middleware throws an exception before processing the work" do
      let(:raise_before_yield) { true }

      it "acks the job" do
        work.expect(:acknowledge, nil)
        begin
          @processor.process(work)
          flunk "Expected #process to raise exception"
        rescue TestProcessorException
        end
      end
    end

    describe "middleware throws an exception after processing the work" do
      let(:raise_after_yield) { true }

      it "acks the job" do
        work.expect(:acknowledge, nil)
        begin
          @processor.process(work)
          flunk "Expected #process to raise exception"
        rescue TestProcessorException
        end
      end
    end

    describe "middleware decides to skip work" do
      let(:skip_job) { true }

      it "acks the job" do
        work.expect(:acknowledge, nil)
        @processor.process(work)
      end
    end

    describe "worker raises an exception" do
      let(:worker_args) { ["boom"] }

      it "acks the job" do
        work.expect(:acknowledge, nil)
        begin
          @processor.process(work)
          flunk "Expected #process to raise exception"
        rescue TestProcessorException
        end
      end
    end

    describe "everything goes well" do
      it "acks the job" do
        work.expect(:acknowledge, nil)
        @processor.process(work)
      end
    end
  end

  describe "retry" do
    class ArgsMutatingServerMiddleware
      def call(worker, item, queue)
        item["args"] = item["args"].map do |arg|
          arg.to_sym if arg.is_a?(String)
        end
        yield
      end
    end

    class ArgsMutatingClientMiddleware
      def call(worker, item, queue, redis_pool)
        item["args"] = item["args"].map do |arg|
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

    describe "middleware mutates the job args and then fails" do
      it "requeues with original arguments" do
        job_data = {"class" => MockWorker.to_s, "args" => ["boom"]}

        retry_stub_called = false
        retry_stub = lambda { |worker, msg, queue, exception|
          retry_stub_called = true
          assert_equal "boom", msg["args"].first
        }

        @processor.instance_variable_get(:@retrier).stub(:attempt_retry, retry_stub) do
          msg = Sidekiq.dump_json(job_data)
          begin
            @processor.process(work(msg))
            flunk "Expected exception"
          rescue TestProcessorException
          end
        end

        assert retry_stub_called
      end
    end
  end

  describe "stats" do
    before do
      Sidekiq.redis { |c| c.flushdb }
    end

    describe "execution" do
      let(:processed_today_key) { "stat:processed:#{Time.now.utc.strftime("%Y-%m-%d")}" }

      it "handles success" do
        Sidekiq::Processor::PROCESSED.reset

        msg = Sidekiq.dump_json({"class" => MockWorker.to_s, "args" => ["myarg"]})
        @processor.process(work(msg))

        metrics = Sidekiq::Processor::PROCESSED.reset
        assert_equal 3, metrics.size
        totals, queues, jobs = metrics
        assert_equal 2, totals.size
        assert_equal 2, queues.size
        assert_equal 2, jobs.size
        assert_equal 1, totals["p"]
        assert_equal 1, queues["default|p"]
        assert_equal 1, jobs["MockWorker|p"]
      end

      it "handles failure" do
        Sidekiq::Processor::PROCESSED.reset

        msg = Sidekiq.dump_json({"class" => MockWorker.to_s, "args" => ["boom"]})
        assert_raises TestProcessorException do
          @processor.process(work(msg))
        end

        metrics = Sidekiq::Processor::PROCESSED.reset
        assert_equal 3, metrics.size
        totals, queues, jobs = metrics
        assert_equal 3, totals.size
        assert_equal 3, queues.size
        assert_equal 3, jobs.size
        assert_equal 1, totals["f"]
        assert_equal 1, queues["default|f"]
        assert_equal 1, jobs["MockWorker|f"]
        # {"f" => 1, "ms" => 0, "p" => 1},
        #  {"q:default|f" => 1, "default|ms" => 0, "default|p" => 1},
        # {"MockWorker|f" => 1, "MockWorker|ms" => 0, "MockWorker|p" => 1}],
      end
    end
  end

  describe "custom job logger class" do
    class CustomJobLogger < Sidekiq::JobLogger
      def call(item, queue)
        yield
      rescue Exception
        raise
      end
    end

    before do
      opts = Sidekiq
      opts[:job_logger] = CustomJobLogger
      opts[:fetch] = Sidekiq::BasicFetch.new(opts)
      @processor = ::Sidekiq::Processor.new(opts) { |pr, ex| }
    end

    it "is called instead default Sidekiq::JobLogger" do
      msg = Sidekiq.dump_json({"class" => MockWorker.to_s, "args" => ["myarg"]})
      @processor.process(work(msg))
      assert_equal 1, $invokes
    end
  end
end
