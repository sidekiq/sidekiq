require_relative 'helper'
require 'sidekiq/scheduled'

class TestScheduled < Sidekiq::Test
  class ScheduledWorker
    include Sidekiq::Worker
    def perform(x)
    end
  end

  describe 'poller' do
    before do
      Sidekiq.redis = REDIS
      Sidekiq.redis do |conn|
        conn.flushdb
      end

      @error_1  = { 'class' => ScheduledWorker.name, 'args' => [0], 'queue' => 'queue_1' }
      @error_2  = { 'class' => ScheduledWorker.name, 'args' => [1], 'queue' => 'queue_2' }
      @error_3  = { 'class' => ScheduledWorker.name, 'args' => [2], 'queue' => 'queue_3' }
      @future_1 = { 'class' => ScheduledWorker.name, 'args' => [3], 'queue' => 'queue_4' }
      @future_2 = { 'class' => ScheduledWorker.name, 'args' => [4], 'queue' => 'queue_5' }
      @future_3 = { 'class' => ScheduledWorker.name, 'args' => [5], 'queue' => 'queue_6' }

      @retry = Sidekiq::RetrySet.new
      @scheduled = Sidekiq::ScheduledSet.new
      @poller = Sidekiq::Scheduled::Poller.new
    end

    class Stopper
      def call(worker_class, message, queue, r)
        yield if message['args'].first.odd?
      end
    end

    it 'executes client middleware' do
      Sidekiq.client_middleware.add Stopper
      begin
        @retry.schedule (Time.now - 60).to_f, @error_1
        @retry.schedule (Time.now - 60).to_f, @error_2
        @scheduled.schedule (Time.now - 60).to_f, @future_2
        @scheduled.schedule (Time.now - 60).to_f, @future_3

        @poller.poll

        Sidekiq.redis do |conn|
          assert_equal 0, conn.llen("queue:queue_1")
          assert_equal 1, conn.llen("queue:queue_2")
          assert_equal 0, conn.llen("queue:queue_5")
          assert_equal 1, conn.llen("queue:queue_6")
        end
      ensure
        Sidekiq.client_middleware.remove Stopper
      end
    end

    it 'should empty the retry and scheduled queues up to the current time' do
      enqueued_time = Time.new(2013, 2, 4)

      Time.stub(:now, enqueued_time) do
        @retry.schedule (Time.now - 60).to_f, @error_1
        @retry.schedule (Time.now - 50).to_f, @error_2
        @retry.schedule (Time.now + 60).to_f, @error_3
        @scheduled.schedule (Time.now - 60).to_f, @future_1
        @scheduled.schedule (Time.now - 50).to_f, @future_2
        @scheduled.schedule (Time.now + 60).to_f, @future_3

        @poller.poll

        Sidekiq.redis do |conn|
          assert_equal 1, conn.llen("queue:queue_1")
          assert_equal enqueued_time.to_f, Sidekiq.load_json(conn.lrange("queue:queue_1", 0, -1)[0])['enqueued_at']
          assert_equal 1, conn.llen("queue:queue_2")
          assert_equal enqueued_time.to_f, Sidekiq.load_json(conn.lrange("queue:queue_2", 0, -1)[0])['enqueued_at']
          assert_equal 1, conn.llen("queue:queue_4")
          assert_equal enqueued_time.to_f, Sidekiq.load_json(conn.lrange("queue:queue_4", 0, -1)[0])['enqueued_at']
          assert_equal 1, conn.llen("queue:queue_5")
          assert_equal enqueued_time.to_f, Sidekiq.load_json(conn.lrange("queue:queue_5", 0, -1)[0])['enqueued_at']
        end

        assert_equal 1, @retry.size
        assert_equal 1, @scheduled.size
      end
    end
  end
end
