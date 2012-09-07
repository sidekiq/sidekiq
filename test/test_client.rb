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
    end

    it 'pushes messages to redis' do
      @redis.expect :rpush, 1, ['queue:foo', String]
      pushed = Sidekiq::Client.push('queue' => 'foo', 'class' => MyWorker, 'args' => [1, 2])
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
      @redis.expect :rpush, 1, ['queue:default', String]
      pushed = MyWorker.perform_async(1, 2)
      assert pushed
      @redis.verify
    end

    it 'handles perform_async on failure' do
      @redis.expect :rpush, nil, ['queue:default', String]
      pushed = MyWorker.perform_async(1, 2)
      refute pushed
      @redis.verify
    end

    it 'enqueues messages to redis' do
      @redis.expect :rpush, 1, ['queue:default', String]
      pushed = Sidekiq::Client.enqueue(MyWorker, 1, 2)
      assert pushed
      @redis.verify
    end

    it 'enqueues messages to redis' do
      @redis.expect :rpush, 1, ['queue:custom_queue', String]
      pushed = Sidekiq::Client.enqueue_to(:custom_queue, MyWorker, 1, 2)
      assert pushed
      @redis.verify
    end

    class QueuedWorker
      include Sidekiq::Worker
      sidekiq_options :queue => :flimflam, :timeout => 1
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

  class BaseWorker
    include Sidekiq::Worker
    sidekiq_options 'retry' => 'base'
  end
  class AWorker < BaseWorker
  end
  class BWorker < BaseWorker
    sidekiq_options 'retry' => 'b'
  end

  describe 'inheritance' do
    it 'should inherit sidekiq options' do
      assert_equal 'base', AWorker.get_sidekiq_options['retry']
      assert_equal 'b', BWorker.get_sidekiq_options['retry']
    end
  end

end
