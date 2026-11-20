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
    ActiveJob::QueueAdapters::SidekiqAdapter.class_variable_set(:@@stopping, false)
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

    it "enqueues jobs of one class and queue with push_bulk" do
      push_bulk_calls = 0
      push_bulk = Sidekiq::Client.method(:push_bulk)
      counting_push_bulk = ->(items) {
        push_bulk_calls += 1
        push_bulk.call(items)
      }

      Sidekiq::Client.stub(:push_bulk, counting_push_bulk) do
        ActiveJob.perform_all_later(AjJob.new(1), AjJob.new(2))
      end

      assert_equal 1, push_bulk_calls
      assert_equal 2, Sidekiq::Queue.new.size
    end

    it "schedules each job of one class at its own time" do
      jobs = [
        AjJob.new(1).set(wait_until: Time.utc(2030, 1, 1)),
        AjJob.new(2).set(wait_until: Time.utc(2031, 1, 1))
      ]

      ActiveJob.perform_all_later(jobs)

      scheduled = Sidekiq::ScheduledSet.new.map { |entry| [entry.args.first["arguments"], entry.at] }
      assert_equal [[[1], Time.utc(2030, 1, 1)], [[2], Time.utc(2031, 1, 1)]], scheduled.sort_by(&:last)
    end

    it "uses push_all for a mix of immediate and scheduled jobs of one class" do
      scheduled = AjJob.new(2).set(wait: 1.hour)

      Sidekiq::Client.stub(:push_bulk, ->(_items) { flunk "expected push_all" }) do
        ActiveJob.perform_all_later(AjJob.new(1), scheduled)
      end

      assert_equal 1, Sidekiq::Queue.new.size
      assert_equal 1, Sidekiq::ScheduledSet.new.size
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

    it "enqueues jobs of different classes in one round trip" do
      recorded_pool = PipelinedCommandRecorder.create_pool(connect: true)

      pipelines = PipelinedCommandRecorder.record do
        Sidekiq::Client.via(recorded_pool) do
          ActiveJob.perform_all_later(
            AjJob.new(1),
            AjJob2.new(2, 3)
          )
        end
      end

      assert_equal 1, pipelines.size
      assert_equal %w[AjJob AjJob2], Sidekiq::Queue.new.map { |job| job["wrapped"] }.sort
    ensure
      recorded_pool&.shutdown(&:close)
    end

    it "sets provider_job_id and successfully_enqueued on each job" do
      jobs = [AjJob.new(1), AjJob2.new(2, 3)]

      ActiveJob.perform_all_later(jobs)

      jobs.each do |job|
        assert_equal 24, job.provider_job_id.size
        assert job.successfully_enqueued?
      end
    end

    it "marks a job a client middleware stops as not enqueued" do
      stopper = Class.new do
        def call(_job_class, job, _queue, _redis)
          yield unless job["wrapped"].to_s == "AjJob2"
        end
      end
      @config.client_middleware.add stopper

      allowed, stopped = jobs = [AjJob.new(1), AjJob2.new(2, 3)]
      enqueued_count = nil
      subscriber = proc { |*, payload| enqueued_count = payload[:enqueued_count] }

      ActiveSupport::Notifications.subscribed(subscriber, "enqueue_all.active_job") do
        ActiveJob.perform_all_later(jobs)
      end

      assert_equal 1, enqueued_count

      assert allowed.successfully_enqueued?
      refute stopped.successfully_enqueued?

      assert_equal 24, allowed.provider_job_id.size
      assert_nil stopped.provider_job_id
    end
  end

  describe "#stopping?" do
    it "can be called without arguments for compatibility with Rails <= 8.1" do
      assert_equal false, ActiveJob::QueueAdapters::SidekiqAdapter.new.stopping?
    end

    it "accepts a job argument" do
      job = Object.new
      assert_equal false, ActiveJob::QueueAdapters::SidekiqAdapter.new.stopping?(job)
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
