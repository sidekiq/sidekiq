# frozen_string_literal: true
require_relative 'helper'
require 'sidekiq/api'

describe Sidekiq::Client do
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
        Sidekiq::Client.push('queue' => 'foo', 'class' => MyWorker, 'args' => :not_an_array)
      end

      assert_raises ArgumentError do
        Sidekiq::Client.push('queue' => 'foo', 'class' => MyWorker, 'args' => [1], 'at' => :not_a_numeric)
      end

      assert_raises ArgumentError do
        Sidekiq::Client.push('queue' => 'foo', 'class' => MyWorker, 'args' => [1], 'tags' => :not_an_array)
      end
    end
  end

  describe 'as instance' do
    it 'handles nil queue' do
      assert_raises ArgumentError do
        Sidekiq::Client.push('class' => 'Blah', 'args' => [1,2,3], 'queue' => "")
      end
    end

    it 'can push' do
      client = Sidekiq::Client.new
      jid = client.push('class' => 'Blah', 'args' => [1,2,3])
      assert_equal 24, jid.size
    end

    it 'allows middleware to stop bulk jobs' do
      mware = Class.new do
        def call(worker_klass,msg,q,r)
          msg['args'][0] == 1 ? yield : false
        end
      end
      client = Sidekiq::Client.new
      client.middleware do |chain|
        chain.add mware
      end
      q = Sidekiq::Queue.new
      q.clear
      result = client.push_bulk('class' => 'Blah', 'args' => [[1],[2],[3]])
      assert_equal 1, result.size
      assert_equal 1, q.size
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
      assert Sidekiq::Client.enqueue_to_in(:custom_queue, 3, MyWorker, 1, 2)
      assert Sidekiq::Client.enqueue_to_in(:custom_queue, -3, MyWorker, 1, 2)
      assert_equal 2, Sidekiq::Queue.new('custom_queue').size
      assert Sidekiq::Client.enqueue_in(3, MyWorker, 1, 2)
      assert QueuedWorker.perform_async(1, 2)
      assert_equal 1, Sidekiq::Queue.new('flimflam').size
    end

    describe 'argument checking' do
      class InterestingWorker
        include Sidekiq::Worker

        def perform(an_argument)
        end
      end

      it 'enqueues jobs with a symbol as an argument' do
        InterestingWorker.perform_async(:symbol)
      end

      it 'enqueues jobs with a Date as an argument' do
        InterestingWorker.perform_async(Date.new(2021, 1, 1))
      end

      it 'enqueues jobs with a Hash with symbols and string as keys as an argument' do
        InterestingWorker.perform_async(
          {
            some: 'hash',
            'with' => 'different_keys'
          }
        )
      end

      it 'enqueues jobs with a Struct as an argument' do
        InterestingWorker.perform_async(
          Struct.new(:x, :y).new(0, 0)
        )
      end

      it 'works with a JSON-friendly deep, nested structure' do
        InterestingWorker.perform_async(
          {
            'foo' => ['a', 'b', 'c'],
            'bar' => ['x', 'y', 'z']
          }
        )
      end

      describe 'strict args is enabled' do
        before do
          Sidekiq.strict_args!
        end

        after do
          Sidekiq.strict_args!(false)
        end

        it 'raises an error when using a symbol as an argument' do
          assert_raises ArgumentError do
            InterestingWorker.perform_async(:symbol)
          end
        end

        it 'raises an error when using a Date as an argument' do
          assert_raises ArgumentError do
            InterestingWorker.perform_async(Date.new(2021, 1, 1))
          end
        end

        it 'raises an error when using a Hash with symbols and string as keys as an argument' do
          assert_raises ArgumentError do
            InterestingWorker.perform_async(
              {
                some: 'hash',
                'with' => 'different_keys'
              }
            )
          end
        end

        it 'raises an error when using a Struct as an argument' do
          assert_raises ArgumentError do
            InterestingWorker.perform_async(
              Struct.new(:x, :y).new(0, 0)
            )
          end
        end

        it 'works with a JSON-friendly deep, nested structure' do
          InterestingWorker.perform_async(
            {
              'foo' => ['a', 'b', 'c'],
              'bar' => ['x', 'y', 'z']
            }
          )
        end

        describe 'worker that takes deep, nested structures' do
          it 'raises an error on JSON-unfriendly structures' do
            assert_raises ArgumentError do
              InterestingWorker.perform_async(
                {
                  'foo' => [:a, :b, :c],
                  bar: ['x', 'y', 'z']
                }
              )
            end
          end
        end
      end
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

    it 'can push jobs scheduled at different times' do
      first_at = Time.new(2019, 1, 1)
      second_at = Time.new(2019, 1, 2)
      jids = Sidekiq::Client.push_bulk('class' => QueuedWorker, 'args' => [[1], [2]], 'at' => [first_at.to_f, second_at.to_f])
      (first_jid, second_jid) = jids
      assert_equal first_at, Sidekiq::ScheduledSet.new.find_job(first_jid).at
      assert_equal second_at, Sidekiq::ScheduledSet.new.find_job(second_jid).at
    end

    it 'can push jobs scheduled using ActiveSupport::Duration' do
      jids = Sidekiq::Client.push_bulk('class' => QueuedWorker, 'args' => [[1], [2]], 'at' => [1.seconds, 111.seconds])
      assert_equal 2, jids.size
    end

    it 'returns the jids for the jobs' do
      Sidekiq::Client.push_bulk('class' => 'QueuedWorker', 'args' => (1..2).to_a.map { |x| Array(x) }).each do |jid|
        assert_match(/[0-9a-f]{12}/, jid)
      end
    end

    it 'handles no jobs' do
      result = Sidekiq::Client.push_bulk('class' => 'QueuedWorker', 'args' => [])
      assert_equal 0, result.size
    end

    describe 'errors' do
      it 'raises ArgumentError with invalid params' do
        assert_raises ArgumentError do
          Sidekiq::Client.push_bulk('class' => 'QueuedWorker', 'args' => [[1], 2])
        end

        assert_raises ArgumentError do
          Sidekiq::Client.push_bulk('class' => 'QueuedWorker', 'args' => [[1], [2]], 'at' => [Time.now.to_f, :not_a_numeric])
        end

        assert_raises ArgumentError do
          Sidekiq::Client.push_bulk('class' => QueuedWorker, 'args' => [[1], [2]], 'at' => [Time.now.to_f])
        end

        assert_raises ArgumentError do
          Sidekiq::Client.push_bulk('class' => QueuedWorker, 'args' => [[1]], 'at' => [Time.now.to_f, Time.now.to_f])
        end
      end
    end

    describe '.perform_bulk' do
      it 'pushes a large set of jobs' do
        jids = MyWorker.perform_bulk((1..1_001).to_a.map { |x| Array(x) })
        assert_equal 1_001, jids.size
      end

      it 'pushes a large set of jobs with a different batch size' do
        jids = MyWorker.perform_bulk((1..1_001).to_a.map { |x| Array(x) }, batch_size: 100)
        assert_equal 1_001, jids.size
      end

      it 'handles no jobs' do
        jids = MyWorker.perform_bulk([])
        assert_equal 0, jids.size
      end

      describe 'errors' do
        it 'raises ArgumentError with invalid params' do
          assert_raises ArgumentError do
            Sidekiq::Client.push_bulk('class' => 'MyWorker', 'args' => [[1], 2])
          end
        end
      end

      describe 'lazy enumerator' do
        it 'enqueues the jobs by evaluating the enumerator' do
          lazy_array = (1..1_001).to_a.map { |x| Array(x) }.lazy
          jids = MyWorker.perform_bulk(lazy_array)
          assert_equal 1_001, jids.size
        end
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

      assert_nil client.push('class' => MyWorker, 'args' => [0])
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
      conn.expect(:pipelined, [0, 1])
      DWorker.sidekiq_options('pool' => ConnectionPool.new(size: 1) { conn })
      DWorker.perform_async(1,2,3)
      conn.verify
    end

    it 'allows #via to point to same Redi' do
      conn = MiniTest::Mock.new
      conn.expect(:pipelined, [0, 1])
      sharded_pool = ConnectionPool.new(size: 1) { conn }
      Sidekiq::Client.via(sharded_pool) do
        Sidekiq::Client.via(sharded_pool) do
          CWorker.perform_async(1,2,3)
        end
      end
      conn.verify
    end

    it 'allows #via to point to different Redi' do
      default = Sidekiq::Client.new.redis_pool

      moo = MiniTest::Mock.new
      moo.expect(:pipelined, [0, 1])
      beef = ConnectionPool.new(size: 1) { moo }

      oink = MiniTest::Mock.new
      oink.expect(:pipelined, [0, 1])
      pork = ConnectionPool.new(size: 1) { oink }

      Sidekiq::Client.via(beef) do
        CWorker.perform_async(1,2,3)
        assert_equal beef, Sidekiq::Client.new.redis_pool
        Sidekiq::Client.via(pork) do
          assert_equal pork, Sidekiq::Client.new.redis_pool
          CWorker.perform_async(1,2,3)
        end
        assert_equal beef, Sidekiq::Client.new.redis_pool
      end
      assert_equal default, Sidekiq::Client.new.redis_pool
      moo.verify
      oink.verify
    end

    it 'allows Resque helpers to point to different Redi' do
      conn = MiniTest::Mock.new
      conn.expect(:pipelined, []) { |*args, &block| block.call(conn) }
      conn.expect(:zadd, 1, [String, Array])
      DWorker.sidekiq_options('pool' => ConnectionPool.new(size: 1) { conn })
      Sidekiq::Client.enqueue_in(10, DWorker, 3)
      conn.verify
    end
  end

  describe 'class attribute race conditions' do
    new_class = -> {
      Class.new do
        class_eval('include Sidekiq::Worker')

        define_method(:foo) { get_sidekiq_options }
      end
    }

    it 'does not explode when new initializing classes from multiple threads' do
      100.times do
        klass = new_class.call

        t1 = Thread.new { klass.sidekiq_options({}) }
        t2 = Thread.new { klass.sidekiq_options({}) }
        t1.join
        t2.join
      end
    end
  end
end
