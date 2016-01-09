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
      Sidekiq.redis{|c| c.flushdb}
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
      def call(worker_class, job, queue, r)
        yield if job['args'].first.odd?
      end
    end

    it 'executes client middleware' do
      Sidekiq.client_middleware.add Stopper
      begin
        @retry.schedule (Time.now - 60).to_f, @error_1
        @retry.schedule (Time.now - 60).to_f, @error_2
        @scheduled.schedule (Time.now - 60).to_f, @future_2
        @scheduled.schedule (Time.now - 60).to_f, @future_3

        @poller.enqueue

        assert_equal 0, Sidekiq::Queue.new("queue_1").size
        assert_equal 1, Sidekiq::Queue.new("queue_2").size
        assert_equal 0, Sidekiq::Queue.new("queue_5").size
        assert_equal 1, Sidekiq::Queue.new("queue_6").size
      ensure
        Sidekiq.client_middleware.remove Stopper
      end
    end

    it 'should empty the retry and scheduled queues up to the current time' do
      created_time  = Time.new(2013, 2, 3)
      enqueued_time = Time.new(2013, 2, 4)

      Time.stub(:now, created_time) do
        @retry.schedule (enqueued_time - 60).to_f, @error_1.merge!('created_at' => created_time.to_f)
        @retry.schedule (enqueued_time - 50).to_f, @error_2.merge!('created_at' => created_time.to_f)
        @retry.schedule (enqueued_time + 60).to_f, @error_3.merge!('created_at' => created_time.to_f)
        @scheduled.schedule (enqueued_time - 60).to_f, @future_1.merge!('created_at' => created_time.to_f)
        @scheduled.schedule (enqueued_time - 50).to_f, @future_2.merge!('created_at' => created_time.to_f)
        @scheduled.schedule (enqueued_time + 60).to_f, @future_3.merge!('created_at' => created_time.to_f)
      end

      Time.stub(:now, enqueued_time) do
        @poller.enqueue

        Sidekiq.redis do |conn|
          %w(queue:queue_1 queue:queue_2 queue:queue_4 queue:queue_5).each do |queue_name|
            assert_equal 1, conn.llen(queue_name)
            job = Sidekiq.load_json(conn.lrange(queue_name, 0, -1)[0])
            assert_equal enqueued_time.to_f, job['enqueued_at']
            assert_equal created_time.to_f,  job['created_at']
          end
        end

        assert_equal 1, @retry.size
        assert_equal 1, @scheduled.size
      end
    end

    def with_sidekiq_option(name, value)
      _original, Sidekiq.options[name] = Sidekiq.options[name], value
      begin
        yield
      ensure
        Sidekiq.options[name] = _original
      end
    end

    it 'generates random intervals that target a configured average' do
      with_sidekiq_option(:poll_interval_average, 10) do
        i = 500
        intervals = Array.new(i){ @poller.send(:random_poll_interval) }

        assert intervals.all?{|x| x >= 5}
        assert intervals.all?{|x| x <= 15}
        assert_in_delta 10, intervals.reduce(&:+).to_f / i, 0.5
      end
    end

    it 'calculates an average poll interval based on the number of known Sidekiq processes' do
      with_sidekiq_option(:average_scheduled_poll_interval, 10) do
        3.times do |i|
          Sidekiq.redis do |conn|
            conn.sadd("processes", "process-#{i}")
            conn.hset("process-#{i}", "info", nil)
          end
        end

        assert_equal 30, @poller.send(:scaled_poll_interval)
      end
    end
  end
end
