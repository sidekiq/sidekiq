require_relative 'helper'
require 'sidekiq/scheduled'

class TestScheduling < Sidekiq::Test
  describe 'middleware' do
    before do
      Sidekiq::Client.instance_variable_set(:@default, nil)
      @redis = Minitest::Mock.new
      # Ugh, this is terrible.
      Sidekiq.instance_variable_set(:@redis, @redis)
      def @redis.multi; [yield] * 2 if block_given?; end
      def @redis.with; yield self; end
    end

    after do
      Sidekiq::Client.instance_variable_set(:@default, nil)
      Sidekiq.instance_variable_set(:@redis, REDIS)
    end

    class ScheduledWorker
      include Sidekiq::Worker
      sidekiq_options :queue => :custom_queue
      def perform(x)
      end
    end

    it 'schedules a job via interval' do
      @redis.expect :zadd, true, ['schedule', Array]
      assert ScheduledWorker.perform_in(600, 'mike')
      @redis.verify
    end

    it 'schedules a job in one month' do
      @redis.expect :zadd, true do |key, args|
        assert_equal 'schedule', key
        assert_in_delta 1.month.since.to_f, args[0][0].to_f, 1
      end
      assert ScheduledWorker.perform_in(1.month, 'mike')
      @redis.verify
    end

    it 'schedules a job via timestamp' do
      @redis.expect :zadd, true, ['schedule', Array]
      assert ScheduledWorker.perform_in(5.days.from_now, 'mike')
      @redis.verify
    end

    it 'schedules job right away on negative timestamp/interval' do
      @redis.expect :sadd,  true, ['queues', 'custom_queue']
      @redis.expect :lpush, true, ['queue:custom_queue', Array]
      assert ScheduledWorker.perform_in(-300, 'mike')
      @redis.verify
    end

    it 'schedules multiple jobs at once' do
      @redis.expect :zadd, true, ['schedule', Array]
      assert Sidekiq::Client.push_bulk('class' => ScheduledWorker, 'args' => [['mike'], ['mike']], 'at' => 600)
      @redis.verify
    end
  end

end
