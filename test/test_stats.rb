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
      msg = Sidekiq.dump_json({ 'class' => DumbWorker.to_s, 'args' => [""] })
      boss = MiniTest::Mock.new

      @redis.with do |conn|

        set = conn.smembers('workers')
        assert_equal 0, set.size

        processor = Sidekiq::Processor.new(boss)
        boss.expect(:processor_done!, nil, [processor])
        boss.expect(:processor_done!, nil, [processor])
        boss.expect(:processor_done!, nil, [processor])

        assert_equal 0, conn.get('stat:failed').to_i
        assert_equal 0, Sidekiq::Stats.processed

        processor.process(msg, 'xyzzy')
        processor.process(msg, 'xyzzy')
        processor.process(msg, 'xyzzy')

        assert_equal 0, conn.get('stat:failed').to_i
        assert_equal 3, Sidekiq::Stats.processed
      end
    end

    it 'updates global stats in the error case' do
      msg = Sidekiq.dump_json({ 'class' => DumbWorker.to_s, 'args' => [nil] })
      boss = MiniTest::Mock.new

      @redis.with do |conn|
        assert_equal [], conn.smembers('workers')
        assert_equal 0, conn.get('stat:failed').to_i
        assert_equal 0, Sidekiq::Stats.processed

        processor = Sidekiq::Processor.new(boss)

        pstr = processor.to_s
        assert_raises RuntimeError do
          processor.process(msg, 'xyzzy')
        end

        assert_equal 1, conn.get('stat:failed').to_i
        assert_equal 1, Sidekiq::Stats.processed
      end
    end

  end
end
