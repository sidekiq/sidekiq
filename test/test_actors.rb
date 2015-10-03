require_relative 'helper'
require 'sidekiq/fetch'

class TestActors < Sidekiq::Test
  class SomeWorker
    include Sidekiq::Worker
  end

  describe 'fetcher' do
    it 'can start and stop' do
      f = Sidekiq::Fetcher.new(nil, { queues: ['default'] })
      f.start
      f.terminate
    end

    it 'can fetch' do
      SomeWorker.perform_async

      mgr = Minitest::Mock.new
      mgr.expect(:assign, nil, [Sidekiq::BasicFetch::UnitOfWork])
      f = Sidekiq::Fetcher.new(mgr, { queues: ['default'] })
      f.start
      f.request_job
      sleep 0.001
      f.terminate
      mgr.verify

      #assert_equal Sidekiq::BasicFetch::UnitOfWork, job.class
    end
  end

  describe 'scheduler' do
    it 'can start and stop' do
      f = Sidekiq::Scheduled::Poller.new
      f.start
      f.terminate
    end

    it 'can schedule' do
      ss = Sidekiq::ScheduledSet.new
      ss.clear

      q = Sidekiq::Queue.new
      q.clear

      SomeWorker.perform_in(0.01)

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

end
