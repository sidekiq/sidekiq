require 'helper'
require 'sidekiq'
require 'sidekiq/processor'

class TestStats < MiniTest::Unit::TestCase
  describe 'with redis' do
    before do
      @redis = Sidekiq.redis = REDIS
      Sidekiq.redis {|c| c.flushdb }
    end

    class DumbWorker
      include Sidekiq::Worker
      sidekiq_options :queue => 'dumbq'

      def perform(arg)
        raise 'bang' if arg == nil
      end
    end

    describe "info counts" do
      before do
        @redis.with do |conn|
          conn.rpush 'queue:foo', '{}'
          conn.sadd 'queues', 'foo'

          3.times { conn.rpush 'queue:bar', '{}' }
          conn.sadd 'queues', 'bar'

          2.times { conn.rpush 'queue:baz', '{}' }
          conn.sadd 'queues', 'baz'
        end
      end

      describe "size" do
        it "returns size of queues" do
          assert_equal 0, Sidekiq.size("foox")
          assert_equal 1, Sidekiq.size(:foo)
          assert_equal 1, Sidekiq.size("foo")
          assert_equal 4, Sidekiq.size("foo", "bar")
          assert_equal 6, Sidekiq.size
        end
      end
    end

  end
end
