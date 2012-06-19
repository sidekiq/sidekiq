require 'helper'
require 'sidekiq/scheduled'

class TestScheduling < MiniTest::Unit::TestCase
  describe 'middleware' do
    before do
      @redis = MiniTest::Mock.new
      # Ugh, this is terrible.
      Sidekiq.instance_variable_set(:@redis, @redis)

      def @redis.with; yield self; end
      def @redis.multi; [yield] * 2 if block_given?; end
    end

    class ScheduledWorker
      include Sidekiq::Worker
      def perform(x)
      end
    end

    it 'schedules a job via interval' do
      timestamp = Time.now.to_f
      Time.stub :now, timestamp do
        @redis.expect :zadd, 1, ['schedule', String, String]
        @redis.expect :rpush, 1, ["schedule:#{(timestamp + 600)}", String]
        assert_equal true, ScheduledWorker.perform_in(600, 'mike')
      end
      @redis.verify
    end

    it 'schedules a job via timestamp' do
      Time.stub :now, Time.now do
        @redis.expect :zadd, 1, ['schedule', String, String]
        @redis.expect :rpush, 1, ["schedule:#{(5.days.from_now.to_f)}", String]
        assert_equal true, ScheduledWorker.perform_in(5.days.from_now, 'mike')
      end
      @redis.verify
    end
  end

  describe 'poller' do
    before do
      @redis = MiniTest::Mock.new
      Sidekiq.instance_variable_set(:@redis, @redis)

      def @redis.with; yield self; end
    end

    it 'should poll like a bad mother...SHUT YO MOUTH' do
      fake_msg = Sidekiq.dump_json({ 'class' => 'Bob', 'args' => [1,2], 'queue' => 'someq' })
      @redis.expect :multi, [[], nil], []
      timestamp = Time.now
      @redis.expect :zrangebyscore, [123], ['schedule', '-inf', timestamp.to_f, { :limit => [0, 1] }]
      @redis.expect :zrangebyscore, [], ['schedule', '-inf', timestamp.to_f, { :limit => [0, 1] }]
      @redis.expect :lpop, fake_msg, ['schedule:123']
      @redis.expect :lpop, nil, ['schedule:123']

      @redis.expect :multi, [[], nil], []
      @redis.expect :llen, 0, ['schedule:123.0']

      @redis.expect :rpush, 1, ['queue:someq', fake_msg]

      inst = Sidekiq::Scheduled::Poller.new
      Time.stub :now, timestamp do
        inst.poll(false)
      end

      @redis.verify
    end
  end
end
