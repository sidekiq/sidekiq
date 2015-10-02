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

end
