require_relative 'helper'
require 'sidekiq/client'
require 'sidekiq/worker'

class TestClient < Sidekiq::Test
  describe 'with mock redis' do
    before do
      @redis = Minitest::Mock.new
      def @redis.multi; [yield] * 2 if block_given?; end
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
      Sidekiq::Client.instance_variable_set(:@default, nil)
    end

    after do
      Sidekiq.redis = REDIS
      Sidekiq::Client.instance_variable_set(:@default, nil)
    end

    it 'raises ArgumentError with invalid params' do
      assert_raises ArgumentError do
        Sidekiq::Client.push('foo', 1)
      end

      assert_raises ArgumentError do
        Sidekiq::Client.push('foo', :class => 'Foo', :noargs => [1, 2])
      end

      assert_raises ArgumentError do
        Sidekiq::Client.push('queue' => 'foo', 'class' => MyWorker, 'noargs' => [1, 2])
      end

      assert_raises ArgumentError do
        Sidekiq::Client.push('queue' => 'foo', 'class' => 42, 'args' => [1, 2])
      end

      assert_raises ArgumentError do
        Sidekiq::Client.push('queue' => 'foo', 'class' => MyWorker, 'args' => 1)
      end
    end

    describe 'as instance' do
      it 'can push' do
        @redis.expect :lpush, 1, ['queue:default', Array]
        client = Sidekiq::Client.new
        jid = client.push('class' => 'Blah', 'args' => [1,2,3])
        assert_equal 24, jid.size
      end

      it 'allows local middleware modification' do
        @redis.expect :lpush, 1, ['queue:default', Array]
        $called = false
        mware = Class.new { def call(worker_klass,msg,q,r); $called = true; msg;end }
        client = Sidekiq::Client.new
        client.middleware do |chain|
          chain.add mware
        end
        client.push('class' => 'Blah', 'args' => [1,2,3])

        assert $called
        assert client.middleware.exists?(mware)
        refute Sidekiq.client_middleware.exists?(mware)
      end
    end

    it 'pushes messages to redis' do
      @redis.expect :lpush, 1, ['queue:foo', Array]
      pushed = Sidekiq::Client.push('queue' => 'foo', 'class' => MyWorker, 'args' => [1, 2])
      assert pushed
      assert_equal 24, pushed.size
      @redis.verify
    end

    it 'pushes messages to redis using a String class' do
      @redis.expect :lpush, 1, ['queue:foo', Array]
      pushed = Sidekiq::Client.push('queue' => 'foo', 'class' => 'MyWorker', 'args' => [1, 2])
      assert pushed
      assert_equal 24, pushed.size
      @redis.verify
    end

    class MyWorker
      include Sidekiq::Worker
    end

    it 'has default options' do
      assert_equal Sidekiq.default_worker_options, MyWorker.get_sidekiq_options
    end

    it 'handles perform_async' do
      @redis.expect :lpush, 1, ['queue:default', Array]
      pushed = MyWorker.perform_async(1, 2)
      assert pushed
      @redis.verify
    end

    it 'enqueues messages to redis' do
      @redis.expect :lpush, 1, ['queue:default', Array]
      pushed = Sidekiq::Client.enqueue(MyWorker, 1, 2)
      assert pushed
      @redis.verify
    end

    it 'enqueues messages to redis' do
      @redis.expect :lpush, 1, ['queue:custom_queue', Array]
      pushed = Sidekiq::Client.enqueue_to(:custom_queue, MyWorker, 1, 2)
      assert pushed
      @redis.verify
    end

    it 'enqueues messages to redis (delayed, custom queue)' do
      @redis.expect :zadd, 1, ['schedule', Array]
      pushed = Sidekiq::Client.enqueue_to_in(:custom_queue, 3.minutes, MyWorker, 1, 2)
      assert pushed
      @redis.verify
    end

    it 'enqueues messages to redis (delayed into past, custom queue)' do
      @redis.expect :lpush, 1, ['queue:custom_queue', Array]
      pushed = Sidekiq::Client.enqueue_to_in(:custom_queue, -3.minutes, MyWorker, 1, 2)
      assert pushed
      @redis.verify
    end

    it 'enqueues messages to redis (delayed)' do
      @redis.expect :zadd, 1, ['schedule', Array]
      pushed = Sidekiq::Client.enqueue_in(3.minutes, MyWorker, 1, 2)
      assert pushed
      @redis.verify
    end

    class QueuedWorker
      include Sidekiq::Worker
      sidekiq_options :queue => :flimflam
    end

    it 'enqueues to the named queue' do
      @redis.expect :lpush, 1, ['queue:flimflam', Array]
      pushed = QueuedWorker.perform_async(1, 2)
      assert pushed
      @redis.verify
    end

    it 'retrieves queues' do
      @redis.expect :smembers, ['bob'], ['queues']
      assert_equal ['bob'], Sidekiq::Queue.all.map(&:name)
    end
  end

  describe 'bulk' do
    after do
      Sidekiq::Queue.new.clear
    end
    it 'can push a large set of jobs at once' do
      jids = Sidekiq::Client.push_bulk('class' => QueuedWorker, 'args' => (1..1_000).to_a.map { |x| Array(x) })
      assert_equal 1_000, jids.size
    end
    it 'can push a large set of jobs at once using a String class' do
      jids = Sidekiq::Client.push_bulk('class' => 'QueuedWorker', 'args' => (1..1_000).to_a.map { |x| Array(x) })
      assert_equal 1_000, jids.size
    end
    it 'returns the jids for the jobs' do
      Sidekiq::Client.push_bulk('class' => 'QueuedWorker', 'args' => (1..2).to_a.map { |x| Array(x) }).each do |jid|
        assert_match(/[0-9a-f]{12}/, jid)
      end
    end
  end

  class BaseWorker
    include Sidekiq::Worker
    sidekiq_options 'retry' => 'base'
  end
  class AWorker < BaseWorker
  end
  class BWorker < BaseWorker
    sidekiq_options 'retry' => 'b'
  end
  class CWorker < BaseWorker
    sidekiq_options 'retry' => 2
  end

  describe 'client middleware' do

    class Stopper
      def call(worker_class, message, queue, r)
        raise ArgumentError unless r
        yield if message['args'].first.odd?
      end
    end

    it 'can stop some of the jobs from pushing' do
      Sidekiq.client_middleware.add Stopper
      begin
        assert_equal nil, Sidekiq::Client.push('class' => MyWorker, 'args' => [0])
        assert_match(/[0-9a-f]{12}/, Sidekiq::Client.push('class' => MyWorker, 'args' => [1]))
        Sidekiq::Client.push_bulk('class' => MyWorker, 'args' => [[0], [1]]).each do |jid|
          assert_match(/[0-9a-f]{12}/, jid)
        end
      ensure
        Sidekiq.client_middleware.remove Stopper
      end
    end
  end

  describe 'inheritance' do
    it 'inherits sidekiq options' do
      assert_equal 'base', AWorker.get_sidekiq_options['retry']
      assert_equal 'b', BWorker.get_sidekiq_options['retry']
    end
  end

  describe 'item normalization' do
    it 'defaults retry to true' do
      assert_equal true, Sidekiq::Client.new.__send__(:normalize_item, 'class' => QueuedWorker, 'args' => [])['retry']
    end

    it "does not normalize numeric retry's" do
      assert_equal 2, Sidekiq::Client.new.__send__(:normalize_item, 'class' => CWorker, 'args' => [])['retry']
    end
  end

  describe 'sharding' do
    class DWorker < BaseWorker
    end
    it 'allows sidekiq_options to point to different Redi' do
      conn = MiniTest::Mock.new
      conn.expect(:multi, [0, 1])
      DWorker.sidekiq_options('pool' => ConnectionPool.new(size: 1) { conn })
      DWorker.perform_async(1,2,3)
      conn.verify
    end
    it 'allows #via to point to different Redi' do
      conn = MiniTest::Mock.new
      conn.expect(:multi, [0, 1])
      default = Sidekiq::Client.new.redis_pool
      sharded_pool = ConnectionPool.new(size: 1) { conn }
      Sidekiq::Client.via(sharded_pool) do
        CWorker.perform_async(1,2,3)
        assert_equal sharded_pool, Sidekiq::Client.new.redis_pool
        assert_raises RuntimeError do
          Sidekiq::Client.via(default) do
            # nothing
          end
        end
      end
      assert_equal default, Sidekiq::Client.new.redis_pool
      conn.verify
    end
    it 'allows Resque helpers to point to different Redi' do
      conn = MiniTest::Mock.new
      conn.expect(:multi, []) { |*args, &block| block.call }
      conn.expect(:zadd, 1, [String, Array])
      DWorker.sidekiq_options('pool' => ConnectionPool.new(size: 1) { conn })
      Sidekiq::Client.enqueue_in(10, DWorker, 3)
      conn.verify
    end
  end
end
