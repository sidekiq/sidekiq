require 'helper'
require 'sidekiq/scheduled'

class TestScheduled < Minitest::Test
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
    end

    it 'should empty the retry and scheduled queues up to the current time' do
      enqueued_time = Time.new(2013, 2, 4)

      Time.stub(:now, enqueued_time) do
        Sidekiq.redis do |conn|
          error_1  = { 'class' => ScheduledWorker.name, 'args' => ["error_1"], 'queue' => 'queue_1' }
          error_2  = { 'class' => ScheduledWorker.name, 'args' => ["error_2"], 'queue' => 'queue_2' }
          error_3  = { 'class' => ScheduledWorker.name, 'args' => ["error_3"], 'queue' => 'queue_3' }
          future_1 = { 'class' => ScheduledWorker.name, 'args' => ["future_1"], 'queue' => 'queue_4' }
          future_2 = { 'class' => ScheduledWorker.name, 'args' => ["future_2"], 'queue' => 'queue_5' }
          future_3 = { 'class' => ScheduledWorker.name, 'args' => ["future_3"], 'queue' => 'queue_6' }

          conn.zadd("retry", (Time.now - 60).to_f.to_s, Sidekiq.dump_json(error_1))
          conn.zadd("retry", (Time.now - 50).to_f.to_s, Sidekiq.dump_json(error_2))
          conn.zadd("retry", (Time.now + 60).to_f.to_s, Sidekiq.dump_json(error_3))
          conn.zadd("schedule", (Time.now - 60).to_f.to_s, Sidekiq.dump_json(future_1))
          conn.zadd("schedule", (Time.now - 50).to_f.to_s, Sidekiq.dump_json(future_2))
          conn.zadd("schedule", (Time.now + 60).to_f.to_s, Sidekiq.dump_json(future_3))

          poller = Sidekiq::Scheduled::Poller.new
          poller.poll

          assert_equal [Sidekiq.dump_json(error_1.merge('enqueued_at' => enqueued_time.to_f))], conn.lrange("queue:queue_1", 0, -1)
          assert_equal [Sidekiq.dump_json(error_2.merge('enqueued_at' => enqueued_time.to_f))], conn.lrange("queue:queue_2", 0, -1)
          assert_equal [Sidekiq.dump_json(future_1.merge('enqueued_at' => enqueued_time.to_f))], conn.lrange("queue:queue_4", 0, -1)
          assert_equal [Sidekiq.dump_json(future_2.merge('enqueued_at' => enqueued_time.to_f))], conn.lrange("queue:queue_5", 0, -1)

          assert_equal [Sidekiq.dump_json(error_3)], conn.zrange("retry", 0, -1)
          assert_equal [Sidekiq.dump_json(future_3)], conn.zrange("schedule", 0, -1)
        end
      end
    end
  end
end
