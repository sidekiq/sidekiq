require 'helper'
require 'sidekiq/manager'
require 'sidekiq/util'

class TestManager < Sidekiq::Test

  describe 'manager' do
    it 'creates N processor instances' do
      mgr = Sidekiq::Manager.new(options)
      assert_equal options[:concurrency], mgr.ready.size
      assert_equal [], mgr.busy
    end

    it 'assigns work to a processor' do
      uow = Object.new
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
      mgr.fetcher = Sidekiq::BasicFetch.new({:queues => []})
      mgr.stop
      mgr.assign(uow)
      uow.verify
    end

    it 'shuts down the system' do
      mgr = Sidekiq::Manager.new(options)
      mgr.fetcher = Sidekiq::BasicFetch.new({:queues => []})
      mgr.stop

      assert mgr.busy.empty?
      assert mgr.ready.empty?
    end

    it 'returns finished processors to the ready pool' do
      fetcher = MiniTest::Mock.new
      fetcher.expect :async, fetcher, []
      fetcher.expect :fetch, nil, []
      mgr = Sidekiq::Manager.new(options)
      mgr.fetcher = fetcher
      init_size = mgr.ready.size
      processor = mgr.ready.pop
      mgr.busy << processor
      mgr.processor_done(processor)

      assert_equal 0, mgr.busy.size
      assert_equal init_size, mgr.ready.size
      fetcher.verify
    end

    it 'throws away dead processors' do
      fetcher = MiniTest::Mock.new
      fetcher.expect :async, fetcher, []
      fetcher.expect :fetch, nil, []
      mgr = Sidekiq::Manager.new(options)
      mgr.fetcher = fetcher
      init_size = mgr.ready.size
      processor = mgr.ready.pop
      mgr.busy << processor
      mgr.processor_died(processor, 'ignored')

      assert_equal 0, mgr.busy.size
      assert_equal init_size, mgr.ready.size
      refute mgr.ready.include?(processor)
      fetcher.verify
    end

    describe 'heartbeat' do
      describe 'proctitle' do
        it 'sets useful info' do
          mgr = Sidekiq::Manager.new(options)
          mgr.heartbeat('identity', heartbeat_data)

          proctitle = $0
          assert_equal $0, "sidekiq #{Sidekiq::VERSION} myapp [0 of 3 busy]"
          $0 = proctitle
        end

        it 'indicates when stopped' do
          mgr = Sidekiq::Manager.new(options)
          mgr.stop
          mgr.heartbeat('identity', heartbeat_data)

          proctitle = $0
          assert_equal $0, "sidekiq #{Sidekiq::VERSION} myapp [0 of 3 busy] stopping"
          $0 = proctitle
        end
      end
    end

    def options
      { :concurrency => 3, :queues => ['default'] }
    end

    def heartbeat_data
      { 'concurrency' => 3, 'tag' => 'myapp' }
    end
  end

end
