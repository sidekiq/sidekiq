require_relative 'helper'

describe Sidekiq::Worker do
  describe '#set' do

    class SetWorker
      include Sidekiq::Worker
      queue_as :foo
      sidekiq_options 'retry' => 12
      def perform
      end
    end

    def setup
      Sidekiq.redis {|c| c.flushdb }
    end

    it "provides basic ActiveJob compatibilility" do
      q = Sidekiq::ScheduledSet.new
      assert_equal 0, q.size
      jid = SetWorker.set(wait_until: 1.hour.from_now).perform_async(123)
      assert jid
      assert_equal 1, q.size
      jid = SetWorker.set(wait: 1.hour).perform_async(123)
      assert jid
      assert_equal 2, q.size

      q = Sidekiq::Queue.new("foo")
      assert_equal 0, q.size
      SetWorker.perform_async
      SetWorker.perform_inline
      SetWorker.perform_sync
      assert_equal 1, q.size

      SetWorker.set(queue: 'xyz').perform_async
      assert_equal 1, Sidekiq::Queue.new("xyz").size
    end

    it 'can be memoized' do
      q = Sidekiq::Queue.new('bar')
      assert_equal 0, q.size
      set = SetWorker.set(queue: :bar, foo: 'qaaz')
      set.perform_async(1)
      set.perform_async(1)
      set.perform_async(1)
      set.perform_async(1)
      assert_equal 4, q.size
      assert_equal 4, q.map{|j| j['jid'] }.uniq.size
      set.perform_in(10, 1)
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

    it 'allows multiple calls' do
      SetWorker.set(queue: :foo).set(bar: 'xyz').perform_async

      q = Sidekiq::Queue.new('foo')
      job = q.first
      assert_equal 'foo', job['queue']
      assert_equal 'xyz', job['bar']
    end

    it 'works with .perform_bulk' do
      q = Sidekiq::Queue.new('bar')
      assert_equal 0, q.size

      set = SetWorker.set(queue: 'bar')
      jids = set.perform_bulk((1..1_001).to_a.map { |x| Array(x) })

      assert_equal 1_001, q.size
      assert_equal 1_001, jids.size
    end

    describe '.perform_bulk and lazy enumerators' do
      it 'evaluates lazy enumerators' do
        q = Sidekiq::Queue.new('bar')
        assert_equal 0, q.size

        set = SetWorker.set('queue' => 'bar')
        lazy_args = (1..1_001).to_a.map { |x| Array(x) }.lazy
        jids = set.perform_bulk(lazy_args)

        assert_equal 1_001, q.size
        assert_equal 1_001, jids.size
      end
    end
  end

  describe '#perform_inline' do
    $my_recorder = []

    class MyCustomWorker
      include Sidekiq::Worker

      def perform(recorder)
        $my_recorder << ['work_performed']
      end
    end

    class MyCustomMiddleware
      def initialize(name, recorder)
        @name = name
        @recorder = recorder
      end

      def call(*args)
        @recorder << "#{@name}-before"
        response = yield
        @recorder << "#{@name}-after"
        return response
      end
    end

    it 'executes middleware & runs job inline' do
      server_chain = Sidekiq::Middleware::Chain.new
      server_chain.add MyCustomMiddleware, "1-server", $my_recorder
      client_chain = Sidekiq::Middleware::Chain.new
      client_chain.add MyCustomMiddleware, "1-client", $my_recorder
      Sidekiq.stub(:server_middleware, server_chain) do
        Sidekiq.stub(:client_middleware, client_chain) do
          MyCustomWorker.perform_inline($my_recorder)
          assert_equal $my_recorder.flatten, %w(1-client-before 1-client-after 1-server-before work_performed 1-server-after)
        end
      end
    end
  end
  
  describe '#serialize' do
    class SerializableWorker
      include Sidekiq::Worker
      sidekiq_options queue: 'some_queue', retry_queue: 'retry_queue', retry: 5, backtrace: 10, tags: ['alpha', '🥇']
      
      def perform(required_positional,
                  optional_positional = "OPTIONAL POSITIONAL",
                  *splat_args)
        
      end
    end
      
    it 'serializes full job info' do
      serialized_job = SerializableWorker.new('required positional argument').serialize
      
      assert_equal "SerializableWorker", serialized_job['class']
      assert_equal ["required positional argument"], serialized_job['args']
      assert_equal 5, serialized_job['retry']
      assert_equal 'some_queue', serialized_job['queue']
      assert_equal 'retry_queue', serialized_job['retry_queue']
      assert_equal 10, serialized_job['backtrace']
      assert_equal ["alpha", "🥇"], serialized_job['tags']
      assert_equal true, serialized_job['normalized']
    end
  end
end
