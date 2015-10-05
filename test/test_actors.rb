require_relative 'helper'
require 'sidekiq/cli'
require 'sidekiq/fetch'
require 'sidekiq/processor'

class TestActors < Sidekiq::Test
  class SomeWorker
    include Sidekiq::Worker
    def perform(slp)
      raise "boom" if slp == "boom"
      sleep(slp) if slp > 0
      $count += 1
    end
  end

  describe 'fetcher' do
    it 'can start and stop' do
      f = Sidekiq::Fetcher.new(nil, { queues: ['default'] })
      f.start
      f.terminate
    end

    it 'can fetch' do
      SomeWorker.perform_async(0)

      mgr = Minitest::Mock.new
      mgr.expect(:assign, nil, [Sidekiq::BasicFetch::UnitOfWork])
      f = Sidekiq::Fetcher.new(mgr, { queues: ['default'] })
      f.start
      f.request_job
      sleep 0.001
      f.terminate
      mgr.verify
    end
  end

  describe 'scheduler' do
    it 'can start and stop' do
      f = Sidekiq::Scheduled::Poller.new
      f.start
      f.terminate
    end

    it 'can schedule' do
      Sidekiq.redis {|c| c.flushdb}

      ss = Sidekiq::ScheduledSet.new
      q = Sidekiq::Queue.new

      SomeWorker.perform_in(0.01, 0)

      assert_equal 0, q.size
      assert_equal 1, ss.size

      sleep 0.01
      s = Sidekiq::Scheduled::Poller.new
      s.enqueue
      assert_equal 1, q.size
      assert_equal 0, ss.size
      s.terminate
    end
  end

  describe 'processor' do
    before do
      $count = 0
    end

    it 'can start and stop' do
      f = Sidekiq::Processor.new(nil)
      f.terminate
    end

    class Mgr
      attr_reader :mutex
      attr_reader :cond
      def initialize
        @mutex = ::Mutex.new
        @cond = ::ConditionVariable.new
      end
      def processor_done(inst)
        @mutex.synchronize do
          @cond.signal
        end
      end
      def processor_died(inst, err)
        @mutex.synchronize do
          @cond.signal
        end
      end
    end

    it 'can process' do
      mgr = Mgr.new

      p = Sidekiq::Processor.new(mgr)
      SomeWorker.perform_async(0)

      job = Sidekiq.redis { |c| c.lpop("queue:default") }
      uow = Sidekiq::BasicFetch::UnitOfWork.new('default', job)
      a = $count
      mgr.mutex.synchronize do
        p.process(uow)
        mgr.cond.wait(mgr.mutex)
      end
      b = $count
      assert_equal a + 1, b

      assert_equal "sleep", p.thread.status
      p.terminate(true)
      assert_equal false, p.thread.status
    end

    it 'deals with errors' do
      mgr = Mgr.new

      p = Sidekiq::Processor.new(mgr)
      SomeWorker.perform_async("boom")

      job = Sidekiq.redis { |c| c.lpop("queue:default") }
      uow = Sidekiq::BasicFetch::UnitOfWork.new('default', job)
      a = $count
      mgr.mutex.synchronize do
        p.process(uow)
        mgr.cond.wait(mgr.mutex)
      end
      b = $count
      assert_equal a, b

      assert_equal false, p.thread.status
      p.terminate(true)
    end

    it 'gracefully kills' do
      mgr = Mgr.new

      p = Sidekiq::Processor.new(mgr)
      SomeWorker.perform_async(0.1)

      job = Sidekiq.redis { |c| c.lpop("queue:default") }
      uow = Sidekiq::BasicFetch::UnitOfWork.new('default', job)
      a = $count
      p.process(uow)
      sleep(0.02)
      p.terminate
      p.kill(true)

      b = $count
      assert_equal a, b
      assert_equal false, p.thread.status
    end
  end
end
