require 'helper'
require 'sidekiq'
require 'sidekiq/processor'

class TestStats < MiniTest::Unit::TestCase
  describe 'with redis' do
    before do
      Sidekiq::Client.redis = @redis = Sidekiq::RedisConnection.create(:url => 'redis://localhost/sidekiq_test')
      @redis.flushdb
    end

    class DumbWorker
      include Sidekiq::Worker

      def perform(redis)
        raise 'bang' if redis == nil
      end
    end

    it 'updates global stats in the success case' do
      msg = { 'class' => DumbWorker.to_s, 'args' => [@redis] }
      boss = MiniTest::Mock.new

      set = @redis.smembers('workers')
      assert_equal 0, set.size

      processor = Sidekiq::Processor.new(boss)
      boss.expect(:processor_done!, nil, [processor])

      # adds to the workers set upon initialize
      set = @redis.smembers('workers')
      assert_equal 1, set.size
      assert_match(/#{Regexp.escape(`hostname`.strip)}/, set.first)

      assert_equal 0, @redis.get('stat:failed').to_i
      assert_equal 0, @redis.get('stat:processed').to_i
      assert_equal 0, @redis.get("stat:processed:#{processor}").to_i

      processor.process(msg, 'xyzzy')
      processor.process(msg, 'xyzzy')
      processor.process(msg, 'xyzzy')

      set = @redis.smembers('workers')
      assert_equal 1, set.size
      assert_match(/#{Regexp.escape(`hostname`.strip)}/, set.first)
      assert_equal 0, @redis.get('stat:failed').to_i
      assert_equal 3, @redis.get('stat:processed').to_i
      assert_equal 3, @redis.get("stat:processed:#{processor}").to_i
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

    it 'should set various stats during processing' do
      skip 'TODO'
    end
  end
end
