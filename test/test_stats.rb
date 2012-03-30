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

      def perform(arg)
        raise 'bang' if arg == nil
      end
    end

    it 'updates global stats in the success case' do
      msg = { 'class' => DumbWorker.to_s, 'args' => [""] }
      boss = MiniTest::Mock.new

      @redis.with do |conn|

        set = conn.smembers('workers')
        assert_equal 0, set.size

        processor = Sidekiq::Processor.new(boss)
        boss.expect(:processor_done!, nil, [processor])

        # adds to the workers set upon initialize
        set = conn.smembers('workers')
        assert_equal 1, set.size
        assert_match(/#{Regexp.escape(`hostname`.strip)}/, set.first)

        assert_equal 0, conn.get('stat:failed').to_i
        assert_equal 0, conn.get('stat:processed').to_i
        assert_equal 0, conn.get("stat:processed:#{processor}").to_i

        processor.process(msg, 'xyzzy')
        processor.process(msg, 'xyzzy')
        processor.process(msg, 'xyzzy')

        set = conn.smembers('workers')
        assert_equal 1, set.size
        assert_match(/#{Regexp.escape(`hostname`.strip)}/, set.first)
        assert_equal 0, conn.get('stat:failed').to_i
        assert_equal 3, conn.get('stat:processed').to_i
        assert_equal 3, conn.get("stat:processed:#{processor}").to_i
      end
    end

    it 'updates global stats in the error case' do
      msg = { 'class' => DumbWorker.to_s, 'args' => [nil] }
      boss = MiniTest::Mock.new

      assert_equal [], @redis.smembers('workers')
      assert_equal 0, @redis.get('stat:failed').to_i
      assert_equal 0, @redis.get('stat:processed').to_i

      processor = Sidekiq::Processor.new(boss)
      assert_equal 1, @redis.smembers('workers').size

      pstr = processor.to_s
      assert_raises RuntimeError do
        processor.process(msg, 'xyzzy')
      end

      set = @redis.smembers('workers')
      assert_equal 0, set.size
      assert_equal 1, @redis.get('stat:failed').to_i
      assert_equal 1, @redis.get('stat:processed').to_i
      assert_equal nil, @redis.get("stat:processed:#{pstr}")
    end

  end
end
