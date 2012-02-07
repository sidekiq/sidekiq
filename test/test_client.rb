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
      Sidekiq::Client.push_unique_only = true
      10.times { Sidekiq::Client.push('customqueue', 'class' => 'Foo', 'args' => [1, 2]) }
      assert_equal Sidekiq::Client.redis.llen("queue:customqueue"), 1
    end

    it 'does push duplicate messages when not configured for unique only' do
      Sidekiq::Client.push_unique_only = false
      10.times { Sidekiq::Client.push('customqueue2', 'class' => 'Foo', 'args' => [1, 2]) }
      assert_equal Sidekiq::Client.redis.llen("queue:customqueue2"), 10
    end
  end

  describe 'with mock redis' do
    before do
      @redis = MiniTest::Mock.new
      def @redis.multi; yield; end
      def @redis.sadd(*); true; end
      Sidekiq::Client.redis = @redis
      Sidekiq::Client.push_unique_only = false
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
      count = Sidekiq::Client.push('foo', 'class' => 'Foo', 'args' => [1, 2])
      assert count > 0
      @redis.verify
    end

    class MyWorker
      include Sidekiq::Worker
      def self.queue
        'foo'
      end
    end

    it 'handles perform_async' do
      @redis.expect :rpush, 1, ['queue:default', String]
      count = MyWorker.perform_async(1, 2)
      assert count > 0
      @redis.verify
    end

    it 'enqueues messages to redis' do
      @redis.expect :rpush, 1, ['queue:foo', String]
      count = Sidekiq::Client.enqueue(MyWorker, 1, 2)
      assert count > 0
      @redis.verify
    end
  end
end
