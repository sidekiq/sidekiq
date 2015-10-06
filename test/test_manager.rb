require_relative 'helper'
require 'sidekiq/manager'

class TestManager < Sidekiq::Test

  describe 'manager' do
    before do
      Sidekiq.redis {|c| c.flushdb }
    end

    def new_manager(opts)
      condvar = Minitest::Mock.new
      condvar.expect(:signal, nil, [])
      Sidekiq::Manager.new(condvar, opts)
    end

    it 'creates N processor instances' do
      mgr = new_manager(options)
      assert_equal options[:concurrency], mgr.ready.size
      assert_equal({}, mgr.in_progress)
    end

    it 'assigns work to a processor' do
      uow = Object.new
      processor = Minitest::Mock.new
      processor.expect(:request_process, nil, [uow])
      processor.expect(:hash, 1234, [])

      mgr = new_manager(options)
      mgr.ready << processor
      mgr.assign(uow)
      assert_equal 1, mgr.in_progress.size

      processor.verify
    end

    it 'requeues work if stopping' do
      uow = Minitest::Mock.new
      uow.expect(:requeue, nil, [])

      mgr = new_manager(options)
      mgr.fetcher = Sidekiq::BasicFetch.new({:queues => []})
      mgr.quiet
      mgr.assign(uow)
      uow.verify
    end

    it 'shuts down the system' do
      mgr = new_manager(options)
      mgr.fetcher = Sidekiq::BasicFetch.new({:queues => []})
      mgr.stop(Time.now)

      assert mgr.in_progress.empty?
      assert mgr.ready.empty?
    end

    it 'returns finished processors to the ready pool' do
      fetcher = MiniTest::Mock.new
      fetcher.expect :request_job, nil, []
      mgr = new_manager(options)
      mgr.fetcher = fetcher
      init_size = mgr.ready.size
      processor = mgr.ready.pop
      mgr.in_progress[processor] = 'abc'
      mgr.processor_done(processor)

      assert_equal 0, mgr.in_progress.size
      assert_equal init_size, mgr.ready.size
      fetcher.verify
    end

    it 'throws away dead processors' do
      fetcher = MiniTest::Mock.new
      fetcher.expect :request_job, nil, []
      mgr = new_manager(options)
      mgr.fetcher = fetcher
      init_size = mgr.ready.size
      processor = mgr.ready.pop
      mgr.in_progress[processor] = 'abc'
      mgr.processor_died(processor, 'ignored')

      assert_equal 0, mgr.in_progress.size
      assert_equal init_size, mgr.ready.size
      refute mgr.ready.include?(processor)
      fetcher.verify
    end

    it 'does not support invalid concurrency' do
      assert_raises(ArgumentError) { new_manager(concurrency: 0) }
      assert_raises(ArgumentError) { new_manager(concurrency: -1) }
    end

    def options
      { :concurrency => 3, :queues => ['default'] }
    end

  end
end
