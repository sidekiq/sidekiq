require_relative 'helper'

class TestClient < Sidekiq::Test
  describe 'errors' do
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
  end

  describe 'as instance' do
    it 'can push' do
      client = Sidekiq::Client.new
      jid = client.push('class' => 'Blah', 'args' => [1,2,3])
      assert_equal 24, jid.size
    end

    it 'allows local middleware modification' do
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

  describe 'client' do
    it 'pushes messages to redis' do
      q = Sidekiq::Queue.new('foo')
      pre = q.size
      jid = Sidekiq::Client.push('queue' => 'foo', 'class' => MyWorker, 'args' => [1, 2])
      assert jid
      assert_equal 24, jid.size
      assert_equal pre + 1, q.size
    end

    it 'pushes messages to redis using a String class' do
      q = Sidekiq::Queue.new('foo')
      pre = q.size
      jid = Sidekiq::Client.push('queue' => 'foo', 'class' => 'MyWorker', 'args' => [1, 2])
      assert jid
      assert_equal 24, jid.size
      assert_equal pre + 1, q.size
    end

    class MyWorker
      include Sidekiq::Worker
    end

    class QueuedWorker
      include Sidekiq::Worker
      sidekiq_options :queue => :flimflam
    end

    it 'enqueues' do
      Sidekiq.redis {|c| c.flushdb }
      assert_equal Sidekiq.default_worker_options, MyWorker.get_sidekiq_options
      assert MyWorker.perform_async(1, 2)
      assert Sidekiq::Client.enqueue(MyWorker, 1, 2)
      assert Sidekiq::Client.enqueue_to(:custom_queue, MyWorker, 1, 2)
      assert_equal 1, Sidekiq::Queue.new('custom_queue').size
      assert Sidekiq::Client.enqueue_to_in(:custom_queue, 3.minutes, MyWorker, 1, 2)
      assert Sidekiq::Client.enqueue_to_in(:custom_queue, -3.minutes, MyWorker, 1, 2)
      assert_equal 2, Sidekiq::Queue.new('custom_queue').size
      assert Sidekiq::Client.enqueue_in(3.minutes, MyWorker, 1, 2)
      assert QueuedWorker.perform_async(1, 2)
      assert_equal 1, Sidekiq::Queue.new('flimflam').size
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
      def call(worker_class, job, queue, r)
        raise ArgumentError unless r
        yield if job['args'].first.odd?
      end
    end

    it 'can stop some of the jobs from pushing' do
      client = Sidekiq::Client.new
      client.middleware do |chain|
        chain.add Stopper
      end

      assert_equal nil, client.push('class' => MyWorker, 'args' => [0])
      assert_match(/[0-9a-f]{12}/, client.push('class' => MyWorker, 'args' => [1]))
      client.push_bulk('class' => MyWorker, 'args' => [[0], [1]]).each do |jid|
        assert_match(/[0-9a-f]{12}/, jid)
      end
    end
  end

  describe 'inheritance' do
    it 'inherits sidekiq options' do
      assert_equal 'base', AWorker.get_sidekiq_options['retry']
      assert_equal 'b', BWorker.get_sidekiq_options['retry']
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

  describe 'Sidekiq::Worker#set' do
    class SetWorker
      include Sidekiq::Worker
      sidekiq_options :queue => :foo, 'retry' => 12
    end

    def setup
      Sidekiq.redis {|c| c.flushdb }
    end

    it 'allows option overrides' do
      q = Sidekiq::Queue.new('bar')
      assert_equal 0, q.size
      assert SetWorker.set(queue: :bar).perform_async(1)
      job = q.first
      assert_equal 'bar', job['queue']
      assert_equal 12, job['retry']
    end

    it 'handles symbols and strings' do
      q = Sidekiq::Queue.new('bar')
      assert_equal 0, q.size
      assert SetWorker.set('queue' => 'bar', :retry => 11).perform_async(1)
      job = q.first
      assert_equal 'bar', job['queue']
      assert_equal 11, job['retry']

      q.clear
      assert SetWorker.perform_async(1)
      assert_equal 0, q.size

      q = Sidekiq::Queue.new('foo')
      job = q.first
      assert_equal 'foo', job['queue']
      assert_equal 12, job['retry']
    end
  end
end
