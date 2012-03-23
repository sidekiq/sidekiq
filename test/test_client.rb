require 'helper'
require 'sidekiq/client'
require 'sidekiq/worker'

class TestClient < MiniTest::Unit::TestCase
  describe 'with real redis' do
    before do
      Sidekiq.redis = REDIS
      Sidekiq.redis.flushdb
    end

    it 'does not push duplicate messages when configured for unique only' do
      Sidekiq.client_middleware.entries.clear
      Sidekiq.client_middleware do |chain|
        chain.add Sidekiq::Middleware::Client::UniqueJobs
      end
      10.times { Sidekiq::Client.push('customqueue', 'class' => 'Foo', 'args' => [1, 2]) }
      assert_equal 1, Sidekiq.redis.llen("queue:customqueue")
    end

    it 'does push duplicate messages when not configured for unique only' do
      Sidekiq.client_middleware.remove(Sidekiq::Middleware::Client::UniqueJobs)
      10.times { Sidekiq::Client.push('customqueue2', 'class' => 'Foo', 'args' => [1, 2]) }
      assert_equal 10, Sidekiq.redis.llen("queue:customqueue2")
    end
  end

  describe 'with mock redis' do
    before do
      @redis = MiniTest::Mock.new
      def @redis.multi; yield if block_given?; end
      def @redis.set(*); true; end
      def @redis.sadd(*); true; end
      def @redis.srem(*); true; end
      def @redis.get(*); nil; end
      def @redis.del(*); nil; end
      def @redis.incrby(*); nil; end
      def @redis.setex(*); true; end
      def @redis.expire(*); true; end
      def @redis.watch(*); true; end
      def @redis.with_connection; yield self; end
      def @redis.with; yield self; end
      def @redis.exec; true; end
      Sidekiq.instance_variable_set(:@redis, @redis)
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
