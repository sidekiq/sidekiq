require 'helper'
require 'sidekiq'
require 'sidekiq/manager'
require 'connection_pool'

class TestManager < MiniTest::Unit::TestCase
  describe 'with redis' do
    before do
      Sidekiq::Client.redis = @redis = Sidekiq::RedisConnection.create(:url => 'redis://localhost/sidekiq_test')
      @redis.flushdb
      $processed = 0
    end

    class IntegrationWorker
      include Sidekiq::Worker

      def perform(a, b)
        $processed += 1
        a + b
      end
    end

    it 'processes messages' do
      Sidekiq::Client.push(:foo, 'class' => IntegrationWorker, 'args' => [1, 2])
      Sidekiq::Client.push(:foo, 'class' => IntegrationWorker, 'args' => [1, 2])

      q = TimedQueue.new
      redis = Sidekiq::RedisConnection.create(:url => 'redis://localhost/sidekiq_test')
      mgr = Sidekiq::Manager.new(redis, :queues => [:foo])
      mgr.when_done do |_|
        q << 'done' if $processed == 2
      end
      mgr.start!
      result = q.timed_pop(1.0)
      assert_equal 'done', result
      mgr.stop
    end
  end
end
