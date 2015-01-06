require_relative 'helper'
require 'sidekiq/manager'

class TestManager < Sidekiq::Test

  describe 'manager' do
    before do
      Sidekiq.redis = REDIS
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
      assert_equal [], mgr.busy
    end

    it 'assigns work to a processor' do
      uow = Object.new
      processor = Minitest::Mock.new
      processor.expect(:async, processor, [])
      processor.expect(:process, nil, [uow])

      mgr = new_manager(options)
      mgr.ready << processor
      mgr.assign(uow)
      assert_equal 1, mgr.busy.size

      processor.verify
    end

    it 'requeues work if stopping' do
      uow = Minitest::Mock.new
      uow.expect(:requeue, nil, [])

      mgr = new_manager(options)
      mgr.fetcher = Sidekiq::BasicFetch.new({:queues => []})
      mgr.stop
      mgr.assign(uow)
      uow.verify
    end

    it 'shuts down the system' do
      mgr = new_manager(options)
      mgr.fetcher = Sidekiq::BasicFetch.new({:queues => []})
      mgr.stop

      assert mgr.busy.empty?
      assert mgr.ready.empty?
    end

    it 'returns finished processors to the ready pool' do
      fetcher = MiniTest::Mock.new
      fetcher.expect :async, fetcher, []
      fetcher.expect :fetch, nil, []
      mgr = new_manager(options)
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
      mgr = new_manager(options)
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
      before do
        uow = Object.new

        @processor = Minitest::Mock.new
        @processor.expect(:async, @processor, [])
        @processor.expect(:process, nil, [uow])

        @mgr = new_manager(options)
        @mgr.ready << @processor
        @mgr.assign(uow)

        @processor.verify
        @proctitle = $0
      end

      after do
        $0 = @proctitle
      end

      describe 'when manager is active' do
        before do
          @mgr.heartbeat('identity', heartbeat_data, Sidekiq.dump_json(heartbeat_data))
        end

        it 'sets useful info to proctitle' do
          assert_equal "sidekiq #{Sidekiq::VERSION} myapp [1 of 3 busy]", $0
        end

        it 'stores process info in redis' do
          info = Sidekiq.redis { |c| c.hmget('identity', 'busy') }
          assert_equal ["1"], info
          expires = Sidekiq.redis { |c| c.pttl('identity') }
          assert_in_delta 60000, expires, 50
        end
      end

      describe 'when manager is stopped' do
        before do
          @processor.expect(:alive?, [])
          @processor.expect(:terminate, [])

          @mgr.stop
          @mgr.processor_done(@processor)
          @mgr.heartbeat('identity', heartbeat_data, Sidekiq.dump_json(heartbeat_data))

          @processor.verify
        end

        it 'indicates stopping status in proctitle' do
          assert_equal "sidekiq #{Sidekiq::VERSION} myapp [0 of 3 busy] stopping", $0
        end

        it 'stores process info in redis' do
          info = Sidekiq.redis { |c| c.hmget('identity', 'busy') }
          assert_equal ["0"], info
          expires = Sidekiq.redis { |c| c.pttl('identity') }
          assert_in_delta 60000, expires, 50
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
