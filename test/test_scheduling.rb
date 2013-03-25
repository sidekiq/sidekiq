require 'helper'
require 'sidekiq/scheduled'

class TestScheduling < MiniTest::Unit::TestCase
  describe 'middleware' do
    before do
      @redis = MiniTest::Mock.new
      # Ugh, this is terrible.
      Sidekiq.instance_variable_set(:@redis, @redis)

      def @redis.with; yield self; end
    end

    class ScheduledWorker
      include Sidekiq::Worker
      def perform(x)
      end
    end

    it 'schedules a job via interval' do
      @redis.expect :zadd, true, ['schedule', Array]
      assert ScheduledWorker.perform_in(600, 'mike')
      @redis.verify
    end

    it 'schedules a job via timestamp' do
      @redis.expect :zadd, true, ['schedule', Array]
      assert ScheduledWorker.perform_in(5.days.from_now, 'mike')
      @redis.verify
    end

    it 'schedules multiple jobs at once' do
      @redis.expect :zadd, true, ['schedule', Array]
      assert Sidekiq::Client.push_bulk('class' => ScheduledWorker, 'args' => [['mike'], ['mike']], 'at' => 600)
      @redis.verify
    end
  end

end
