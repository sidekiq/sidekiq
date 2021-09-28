require_relative 'helper'

describe Sidekiq::Worker do
  describe '#set' do

    class SetWorker
      include Sidekiq::Worker
      queue_as :foo
      sidekiq_options 'retry' => 12
    end

    def setup
      Sidekiq.redis {|c| c.flushdb }
    end

    it "provides basic ActiveJob compatibilility" do
      q = Sidekiq::ScheduledSet.new
      assert_equal 0, q.size
      jid = SetWorker.set(wait_until: 1.hour).perform_async(123)
      assert jid
      assert_equal 1, q.size

      q = Sidekiq::Queue.new("foo")
      assert_equal 0, q.size
      SetWorker.perform_async
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
  end
end
