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

    it 'updates global stats in the success case' do
      msg = Sidekiq.dump_json({ 'class' => DumbWorker.to_s, 'args' => [""] })
      boss = MiniTest::Mock.new

      @redis.with do |conn|

        set = conn.smembers('workers')
        assert_equal 0, set.size

        processor = Sidekiq::Processor.new(boss)
        boss.expect(:processor_done!, nil, [processor])
        boss.expect(:processor_done!, nil, [processor])
        boss.expect(:processor_done!, nil, [processor])

        assert_equal 0, Sidekiq.info[:failed]
        assert_equal 0, Sidekiq.info[:processed]

        processor.process(msg, 'xyzzy')
        processor.process(msg, 'xyzzy')
        processor.process(msg, 'xyzzy')

        assert_equal 0, Sidekiq.info[:failed]
        assert_equal 3, Sidekiq.info[:processed]
      end
    end

    it 'updates global stats in the error case' do
      msg = Sidekiq.dump_json({ 'class' => DumbWorker.to_s, 'args' => [nil] })
      boss = MiniTest::Mock.new

      @redis.with do |conn|
        assert_equal [], conn.smembers('workers')
        assert_equal 0, Sidekiq.info[:failed]
        assert_equal 0, Sidekiq.info[:processed]

        processor = Sidekiq::Processor.new(boss)

        pstr = processor.to_s
        assert_raises RuntimeError do
          processor.process(msg, 'xyzzy')
        end

        assert_equal 1, Sidekiq.info[:failed]
        assert_equal 1, Sidekiq.info[:processed]
      end
    end

    describe "info counts" do
      before do
        @redis.with do |conn|
          conn.rpush 'queue:foo', '{}'
          conn.sadd 'queues', 'foo'

          conn.rpush 'queue:bar', '{}'
          conn.rpush 'queue:bar', '{}'
          conn.sadd 'queues', 'bar'

          conn.rpush 'queue:baz', '{}'
          conn.sadd 'queues', 'baz'
        end
      end

      describe "queues_with_sizes" do
        it "returns queue names and corresponding job counts" do
          assert_equal [["foo", 1], ["baz", 1], ["bar", 2]], Sidekiq.info[:queues_with_sizes]
        end
      end

      describe "backlog" do
        it "returns count of all jobs yet to be processed" do
          assert_equal 4, Sidekiq.info[:backlog]
        end
      end

      describe "size" do
        it "returns size of queues" do
          assert_equal 0, Sidekiq.size("foox")
          assert_equal 1, Sidekiq.size(:foo)
          assert_equal 1, Sidekiq.size("foo")
          assert_equal 3, Sidekiq.size("foo", "bar")
          assert_equal 4, Sidekiq.size
        end
      end
    end

  end
end
