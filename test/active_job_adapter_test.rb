# frozen_string_literal: true

require_relative "helper"
require "sidekiq/api"

module JobBuffer
  class << self
    def clear
      values.clear
    end

    def add(value)
      values << value
    end

    def values
      @values ||= []
    end
  end
end

class AjJob < ActiveJob::Base
  def perform(arg)
    JobBuffer.add(arg)
  end
end

class AjJob2 < ActiveJob::Base
  def perform(arg1, arg2)
    JobBuffer.add([arg1, arg2])
  end
end

module ProfileableJob
  attr_accessor :profile

  def set(options = {})
    self.profile = options[:profile] || options["profile"]
    super
  end
end

class ProfileableAjJob < ActiveJob::Base
  include ProfileableJob

  def perform
  end
end

describe "SidekiqAdapter" do
  before do
    @config = reset!
    JobBuffer.clear

    require "sidekiq/testing"
    Sidekiq::Testing.disable!
  end

  after do
    Sidekiq::Testing.disable!
  end

  it "enqueues a job" do
    instance = AjJob.perform_later(1)
    q = Sidekiq::Queue.new

    assert_equal 1, q.size
    assert_equal 24, instance.provider_job_id.size

    job = q.first
    assert_equal "Sidekiq::ActiveJob::Wrapper", job["class"]
    assert_equal "AjJob", job["wrapped"]
  end

  it "schedules a job" do
    instance = AjJob.set(wait: 1.hour).perform_later(1)
    ss = Sidekiq::ScheduledSet.new
    assert_equal 1, ss.size

    job = ss.find_job(instance.provider_job_id)
    assert_equal "default", job["queue"]
    assert_equal "Sidekiq::ActiveJob::Wrapper", job["class"]
    assert_equal "AjJob", job["wrapped"]
  end

  it "runs a job inline" do
    Sidekiq::Testing.inline! do
      AjJob.perform_later(1)
      assert_equal 1, JobBuffer.values.last
    end
  end

  describe "#enqueue_all" do
    it "runs multiple queued jobs" do
      Sidekiq::Testing.inline! do
        ActiveJob.perform_all_later(AjJob.new(1), AjJob.new(2))
        assert_equal [1, 2], JobBuffer.values
      end
    end

    it "runs multiple queued jobs of different classes" do
      Sidekiq::Testing.inline! do
        ActiveJob.perform_all_later(AjJob.new(1), AjJob2.new(2, 3))
        assert_equal [1, [2, 3]], JobBuffer.values
      end
    end

    it "enqueues jobs with schedules" do
      scheduled_job_1 = AjJob.new("Scheduled 2014")
      scheduled_job_1.set(wait_until: Time.utc(2014, 1, 1))

      scheduled_job_2 = AjJob.new("Scheduled 2015")
      scheduled_job_2.set(wait_until: Time.utc(2015, 1, 1))

      Sidekiq::Testing.inline! do
        ActiveJob.perform_all_later(scheduled_job_1, scheduled_job_2)
        assert_equal ["Scheduled 2014", "Scheduled 2015"], JobBuffer.values
      end
    end

    it "instruments perform_all_later" do
      jobs = [AjJob.new(1), AjJob.new(2)]
      called = false

      subscriber = proc do |*, payload|
        called = true
        assert payload[:adapter]
        assert_equal jobs, payload[:jobs]
        assert_equal 2, payload[:enqueued_count]
      end

      ActiveSupport::Notifications.subscribed(subscriber, "enqueue_all.active_job") do
        ActiveJob.perform_all_later(jobs)
      end

      assert called
    end
  end

  describe "profiling support" do
    it "enqueues a job to be profiled" do
      ProfileableAjJob.set(profile: "oli").perform_later
      q = Sidekiq::Queue.new

      assert_equal 1, q.size

      job = q.first
      assert_equal "ProfileableAjJob", job["wrapped"]
      assert_equal "oli", job["profile"]
    end

    it "schedules a job to be profiled" do
      instance = ProfileableAjJob.set(wait: 1.hour, profile: "oli").perform_later
      ss = Sidekiq::ScheduledSet.new
      assert_equal 1, ss.size

      job = ss.find_job(instance.provider_job_id)
      assert_equal "ProfileableAjJob", job["wrapped"]
      assert_equal "oli", job["profile"]
    end

    it "does not add an extra 'profile' key to the payload when no profile is requested" do
      ProfileableAjJob.perform_later
      q = Sidekiq::Queue.new

      assert_equal 1, q.size

      job = q.first
      refute_includes(job.item.keys, "profile")

      scheduled_instance = ProfileableAjJob.set(wait: 1.hour).perform_later
      ss = Sidekiq::ScheduledSet.new
      assert_equal 1, ss.size

      scheduled_job = ss.find_job(scheduled_instance.provider_job_id)
      refute_includes(scheduled_job.item.keys, "profile")
    end
  end
end
