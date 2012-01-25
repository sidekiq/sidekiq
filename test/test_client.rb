require 'helper'
require 'sidekiq/client'
require 'sidekiq/worker'

class TestClient < MiniTest::Unit::TestCase
  describe 'with mock redis' do
    before do
      @redis = MiniTest::Mock.new
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
