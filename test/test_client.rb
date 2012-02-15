require 'helper'
require 'sidekiq/client'
require 'sidekiq/worker'

class TestClient < MiniTest::Unit::TestCase
  describe 'with real redis' do
    before do
      Sidekiq::Client.redis = Redis.connect(:url => 'redis://localhost/sidekiq_test')
      Sidekiq::Client.redis.flushdb
    end

    it 'does not push duplicate messages when configured for unique only' do
      Sidekiq::Client.middleware.entries.clear
      Sidekiq::Client.middleware.register do
        use Sidekiq::Middleware::Client::UniqueJobs, Sidekiq::Client.redis
        use Sidekiq::Middleware::Client::ResqueWebCompatibility, Sidekiq::Client.redis
      end
      10.times { Sidekiq::Client.push('customqueue', 'class' => 'Foo', 'args' => [1, 2]) }
      assert_equal 1, Sidekiq::Client.redis.llen("queue:customqueue")
    end

    it 'does push duplicate messages when not configured for unique only' do
      Sidekiq::Client.middleware.unregister(Sidekiq::Middleware::Client::UniqueJobs)
      10.times { Sidekiq::Client.push('customqueue2', 'class' => 'Foo', 'args' => [1, 2]) }
      assert_equal 10, Sidekiq::Client.redis.llen("queue:customqueue2")
    end
  end

  describe 'with mock redis' do
    before do
      @redis = MiniTest::Mock.new
      def @redis.multi; yield; end
      def @redis.set(*); true; end
      def @redis.sadd(*); true; end
      def @redis.srem(*); true; end
      def @redis.get(*); nil; end
      def @redis.del(*); nil; end
      def @redis.incrby(*); nil; end
      def @redis.setex(*); nil; end
      def @redis.expire(*); true; end
      Sidekiq::Client.redis = @redis
    end

    it 'raises ArgumentError with invalid params' do
      assert_raises ArgumentError do
        Sidekiq::Client.push('foo', 1)
      end

      assert_raises ArgumentError do
        Sidekiq::Client.push('foo', :class => 'Foo', :noargs => [1, 2])
      end
    end

    it 'pushes messages to redis' do
      @redis.expect :rpush, 1, ['queue:foo', String]
      pushed = Sidekiq::Client.push('foo', 'class' => 'Foo', 'args' => [1, 2])
      assert pushed
      @redis.verify
    end

    class MyWorker
      include Sidekiq::Worker
    end

    it 'handles perform_async' do
      @redis.expect :rpush, 1, ['queue:default', String]
      pushed = MyWorker.perform_async(1, 2)
      assert pushed
      @redis.verify
    end

    it 'enqueues messages to redis' do
      @redis.expect :rpush, 1, ['queue:default', String]
      pushed = Sidekiq::Client.enqueue(MyWorker, 1, 2)
      assert pushed
      @redis.verify
    end

    class QueuedWorker
      include Sidekiq::Worker

      queue :flimflam
    end

    it 'enqueues to the named queue' do
      @redis.expect :rpush, 1, ['queue:flimflam', String]
      pushed = QueuedWorker.perform_async(1, 2)
      assert pushed
      @redis.verify
    end

    it 'retrieves queues' do
      @redis.expect :smembers, ['bob'], ['queues']
      assert_equal ['bob'], Sidekiq::Client.registered_queues
    end

    it 'retrieves workers' do
      @redis.expect :smembers, ['bob'], ['workers']
      assert_equal ['bob'], Sidekiq::Client.registered_workers
    end
  end
end
