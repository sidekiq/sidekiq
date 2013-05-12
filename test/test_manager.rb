require 'helper'
require 'sidekiq/manager'

class TestManager < Minitest::Test

  describe 'manager' do
    it 'creates N processor instances' do
      mgr = Sidekiq::Manager.new(options)
      assert_equal options[:concurrency], mgr.ready.size
      assert_equal [], mgr.busy
      assert mgr.fetcher
    end

    it 'fetches upon start' do
      mgr = Sidekiq::Manager.new(options)
      count = options[:concurrency]

      fetch_mock = Minitest::Mock.new
      count.times { fetch_mock.expect(:fetch, nil, []) }
      async_mock = Minitest::Mock.new
      count.times { async_mock.expect(:async, fetch_mock, []) }
      mgr.fetcher = async_mock
      mgr.start

      fetch_mock.verify
      async_mock.verify
    end

    it 'assigns work to a processor' do
      uow = Minitest::Mock.new
      processor = Minitest::Mock.new
      processor.expect(:async, processor, [])
      processor.expect(:process, nil, [uow])

      mgr = Sidekiq::Manager.new(options)
      mgr.ready << processor
      mgr.assign(uow)
      assert_equal 1, mgr.busy.size

      processor.verify
    end

    it 'requeues work if stopping' do
      uow = Minitest::Mock.new
      uow.expect(:requeue, nil, [])

      mgr = Sidekiq::Manager.new(options)
      mgr.stop
      mgr.assign(uow)
      uow.verify
    end

    it 'shuts down the system' do
      mgr = Sidekiq::Manager.new(options)
      mgr.stop

      assert mgr.busy.empty?
      assert mgr.ready.empty?
      refute mgr.fetcher.alive?
    end

    it 'returns finished processors to the ready pool' do
      mgr = Sidekiq::Manager.new(options)
      init_size = mgr.ready.size
      processor = mgr.ready.pop
      mgr.busy << processor
      mgr.processor_done(processor)

      assert_equal 0, mgr.busy.size
      assert_equal init_size, mgr.ready.size
    end

    it 'throws away dead processors' do
      mgr = Sidekiq::Manager.new(options)
      init_size = mgr.ready.size
      processor = mgr.ready.pop
      mgr.busy << processor
      mgr.processor_died(processor, 'ignored')

      assert_equal 0, mgr.busy.size
      assert_equal init_size, mgr.ready.size
      refute mgr.ready.include?(processor)
    end

    def options
      { :concurrency => 3, :queues => ['default'] }
    end
  end

end
