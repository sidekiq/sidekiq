require_relative 'helper'
require 'sidekiq/scheduled'

class TestScheduling < Sidekiq::Test
  describe 'middleware' do
    class ScheduledWorker
      include Sidekiq::Worker
      sidekiq_options :queue => :custom_queue
      def perform(x)
      end
    end

    it 'schedules jobs' do
      ss = Sidekiq::ScheduledSet.new
      ss.clear

      assert_equal 0, ss.size

      assert ScheduledWorker.perform_in(600, 'mike')
      assert_equal 1, ss.size

      assert ScheduledWorker.perform_in(1.month, 'mike')
      assert_equal 2, ss.size

      assert ScheduledWorker.perform_in(5.days.from_now, 'mike')
      assert_equal 3, ss.size

      q = Sidekiq::Queue.new("custom_queue")
      qs = q.size
      assert ScheduledWorker.perform_in(-300, 'mike')
      assert_equal 3, ss.size
      assert_equal qs+1, q.size

      assert Sidekiq::Client.push_bulk('class' => ScheduledWorker, 'args' => [['mike'], ['mike']], 'at' => 600)
      assert_equal 5, ss.size
    end

    it 'removes the enqueued_at field when scheduling' do
      ss = Sidekiq::ScheduledSet.new
      ss.clear

      assert ScheduledWorker.perform_in(1.month, 'mike')
      job = ss.first
      assert job['created_at']
      refute job['enqueued_at']
    end
  end

end
