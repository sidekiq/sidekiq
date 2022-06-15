# frozen_string_literal: true

require_relative "helper"
require "sidekiq/api"
require "active_support/core_ext/integer/time"

describe "job scheduling" do
  describe "middleware" do
    class SomeScheduledWorker
      include Sidekiq::Job
      sidekiq_options queue: :custom_queue
      def perform(x)
      end
    end

    # Assume we can pass any class as time to perform_in
    class TimeDuck
      def to_f
        42.0
      end
    end

    it "schedules jobs" do
      ss = Sidekiq::ScheduledSet.new
      ss.clear

      assert_equal 0, ss.size

      assert SomeScheduledWorker.perform_in(600, "mike")
      assert_equal 1, ss.size

      assert SomeScheduledWorker.perform_in(1.month, "mike")
      assert_equal 2, ss.size

      assert SomeScheduledWorker.perform_in(5.days.from_now, "mike")
      assert_equal 3, ss.size

      q = Sidekiq::Queue.new("custom_queue")
      qs = q.size
      assert SomeScheduledWorker.perform_in(-300, "mike")
      assert_equal 3, ss.size
      assert_equal qs + 1, q.size

      assert Sidekiq::Client.push_bulk("class" => SomeScheduledWorker, "args" => [["mike"], ["mike"]], "at" => Time.now.to_f + 100)
      assert_equal 5, ss.size

      assert SomeScheduledWorker.perform_in(TimeDuck.new, "samwise")
      assert_equal 6, ss.size
    end

    it "removes the enqueued_at field when scheduling" do
      ss = Sidekiq::ScheduledSet.new
      ss.clear

      assert SomeScheduledWorker.perform_in(1.month, "mike")
      job = ss.first
      assert job["created_at"]
      refute job["enqueued_at"]
    end

    it "removes the enqueued_at field when scheduling in bulk" do
      ss = Sidekiq::ScheduledSet.new
      ss.clear

      assert Sidekiq::Client.push_bulk("class" => SomeScheduledWorker, "args" => [["mike"], ["mike"]], "at" => Time.now.to_f + 100)
      job = ss.first
      assert job["created_at"]
      refute job["enqueued_at"]
    end
  end
end
