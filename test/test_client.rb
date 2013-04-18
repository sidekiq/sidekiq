require 'helper'
require 'sidekiq/client'
require 'sidekiq/worker'

class TestClient < MiniTest::Unit::TestCase
  describe 'with mock redis' do
    before do
      @redis = MiniTest::Mock.new
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
      assert_equal Sidekiq::Worker::ClassMethods::DEFAULT_OPTIONS, MyWorker.get_sidekiq_options
    end

    it 'handles perform_async' do
      @redis.expect :lpush, 1, ['queue:default', Array]
      pushed = MyWorker.perform_async(1, 2)
      assert pushed
      @redis.verify
    end

    it 'handles perform_async on failure' do
      @redis.expect :lpush, nil, ['queue:default', Array]
      pushed = MyWorker.perform_async(1, 2)
      refute pushed
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
      assert_equal ['bob'], Sidekiq::Client.registered_queues
    end

    it 'retrieves workers' do
      @redis.expect :smembers, ['bob'], ['workers']
      assert_equal ['bob'], Sidekiq::Client.registered_workers
    end
  end

  describe 'bulk' do
    after do
      Sidekiq::Queue.new.clear
    end
    it 'can push a large set of jobs at once' do
      count = Sidekiq::Client.push_bulk('class' => QueuedWorker, 'args' => (1..1_000).to_a.map { |x| Array(x) })
      assert_equal 1_000, count
    end
    it 'can push a large set of jobs at once using a String class' do
      count = Sidekiq::Client.push_bulk('class' => 'QueuedWorker', 'args' => (1..1_000).to_a.map { |x| Array(x) })
      assert_equal 1_000, count
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
      def call(worker_class, message, queue)
        yield if message['args'].first.odd?
      end
    end

    it 'can stop some of the jobs from pushing' do
      Sidekiq.client_middleware.add Stopper
      begin
        assert_equal nil, Sidekiq::Client.push('class' => MyWorker, 'args' => [0])
        assert_match /[0-9a-f]{12}/, Sidekiq::Client.push('class' => MyWorker, 'args' => [1])
        assert_equal 1, Sidekiq::Client.push_bulk('class' => MyWorker, 'args' => [[0], [1]])
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
      assert_equal true, Sidekiq::Client.send(:normalize_item, 'class' => QueuedWorker, 'args' => [])['retry']
    end

    it "does not normalize numeric retry's" do
      assert_equal 2, Sidekiq::Client.send(:normalize_item, 'class' => CWorker, 'args' => [])['retry']
    end
  end
end
