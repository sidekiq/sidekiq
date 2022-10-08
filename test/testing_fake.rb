# frozen_string_literal: true

require_relative "helper"
class PerformError < RuntimeError; end

class DirectWorker
  include Sidekiq::Job
  def perform(a, b)
    a + b
  end
end

class EnqueuedWorker
  include Sidekiq::Job
  def perform(a, b)
    a + b
  end
end

class StoredWorker
  include Sidekiq::Job
  def perform(error)
    raise PerformError if error
  end
end

class SpecificJidWorker
  include Sidekiq::Job
  sidekiq_class_attribute :count
  self.count = 0
  def perform(worker_jid)
    return unless worker_jid == jid
    self.class.count += 1
  end
end

class FirstWorker
  include Sidekiq::Job
  sidekiq_class_attribute :count
  self.count = 0
  def perform
    self.class.count += 1
  end
end

class SecondWorker
  include Sidekiq::Job
  sidekiq_class_attribute :count
  self.count = 0
  def perform
    self.class.count += 1
  end
end

class ThirdWorker
  include Sidekiq::Job
  sidekiq_class_attribute :count
  def perform
    FirstWorker.perform_async
    SecondWorker.perform_async
  end
end

class QueueWorker
  include Sidekiq::Job
  def perform(a, b)
    a + b
  end
end

class AltQueueWorker
  include Sidekiq::Job
  sidekiq_options queue: :alt
  def perform(a, b)
    a + b
  end
end

describe "Sidekiq::Testing.fake" do
  before do
    require "sidekiq/testing"
    Sidekiq::Testing.fake!
    EnqueuedWorker.jobs.clear
    DirectWorker.jobs.clear
  end

  after do
    Sidekiq::Testing.disable!
    Sidekiq::Queues.clear_all
  end

  it "stubs the async call" do
    assert_equal 0, DirectWorker.jobs.size
    assert DirectWorker.perform_async(1, 2)
    assert_in_delta Time.now.to_f, DirectWorker.jobs.last["enqueued_at"], 0.1
    assert_equal 1, DirectWorker.jobs.size
    assert DirectWorker.perform_in(10, 1, 2)
    refute DirectWorker.jobs.last["enqueued_at"]
    assert_equal 2, DirectWorker.jobs.size
    assert DirectWorker.perform_at(10, 1, 2)
    assert_equal 3, DirectWorker.jobs.size
    soon = (Time.now.to_f + 10)
    assert_in_delta soon, DirectWorker.jobs.last["at"], 0.1
  end

  it "stubs the enqueue call" do
    assert_equal 0, EnqueuedWorker.jobs.size
    assert Sidekiq::Client.enqueue(EnqueuedWorker, 1, 2)
    assert_equal 1, EnqueuedWorker.jobs.size
  end

  it "stubs the enqueue_to call" do
    assert_equal 0, EnqueuedWorker.jobs.size
    assert Sidekiq::Client.enqueue_to("someq", EnqueuedWorker, 1, 2)
    assert_equal 1, Sidekiq::Queues["someq"].size
  end

  it "executes all stored jobs" do
    assert StoredWorker.perform_async(false)
    assert StoredWorker.perform_async(true)

    assert_equal 2, StoredWorker.jobs.size
    assert_raises PerformError do
      StoredWorker.drain
    end
    assert_equal 0, StoredWorker.jobs.size
  end

  it "execute only jobs with assigned JID" do
    4.times do |i|
      jid = SpecificJidWorker.perform_async(nil)
      SpecificJidWorker.jobs[-1]["args"] = if i % 2 == 0
        ["wrong_jid"]
      else
        [jid]
      end
    end

    SpecificJidWorker.perform_one
    assert_equal 0, SpecificJidWorker.count

    SpecificJidWorker.perform_one
    assert_equal 1, SpecificJidWorker.count

    SpecificJidWorker.drain
    assert_equal 2, SpecificJidWorker.count
  end

  it "round trip serializes the job arguments" do
    assert_raises ArgumentError do
      StoredWorker.perform_async(:mike)
    end

    Sidekiq.strict_args!(false)
    assert StoredWorker.perform_async(:mike)
    job = StoredWorker.jobs.first
    assert_equal "mike", job["args"].first
    StoredWorker.clear
  ensure
    Sidekiq.strict_args!(:raise)
  end

  it "perform_one runs only one job" do
    DirectWorker.perform_async(1, 2)
    DirectWorker.perform_async(3, 4)
    assert_equal 2, DirectWorker.jobs.size

    DirectWorker.perform_one
    assert_equal 1, DirectWorker.jobs.size

    DirectWorker.clear
  end

  it "perform_one raise error upon empty queue" do
    DirectWorker.clear
    assert_raises Sidekiq::EmptyQueueError do
      DirectWorker.perform_one
    end
  end

  it "clears jobs across all workers" do
    Sidekiq::Job.jobs.clear
    FirstWorker.count = 0
    SecondWorker.count = 0

    assert_equal 0, FirstWorker.jobs.size
    assert_equal 0, SecondWorker.jobs.size

    FirstWorker.perform_async
    SecondWorker.perform_async

    assert_equal 1, FirstWorker.jobs.size
    assert_equal 1, SecondWorker.jobs.size

    Sidekiq::Job.clear_all

    assert_equal 0, FirstWorker.jobs.size
    assert_equal 0, SecondWorker.jobs.size

    assert_equal 0, FirstWorker.count
    assert_equal 0, SecondWorker.count
  end

  it "drains jobs across all workers" do
    Sidekiq::Job.jobs.clear
    FirstWorker.count = 0
    SecondWorker.count = 0

    assert_equal 0, FirstWorker.jobs.size
    assert_equal 0, SecondWorker.jobs.size

    assert_equal 0, FirstWorker.count
    assert_equal 0, SecondWorker.count

    FirstWorker.perform_async
    SecondWorker.perform_async

    assert_equal 1, FirstWorker.jobs.size
    assert_equal 1, SecondWorker.jobs.size

    Sidekiq::Job.drain_all

    assert_equal 0, FirstWorker.jobs.size
    assert_equal 0, SecondWorker.jobs.size

    assert_equal 1, FirstWorker.count
    assert_equal 1, SecondWorker.count
  end

  it "clears the jobs of workers having their queue name defined as a symbol" do
    assert_equal Symbol, AltQueueWorker.sidekiq_options["queue"].class

    AltQueueWorker.perform_async
    assert_equal 1, AltQueueWorker.jobs.size
    assert_equal 1, Sidekiq::Queues[AltQueueWorker.sidekiq_options["queue"].to_s].size

    AltQueueWorker.clear
    assert_equal 0, AltQueueWorker.jobs.size
    assert_equal 0, Sidekiq::Queues[AltQueueWorker.sidekiq_options["queue"].to_s].size
  end

  it "drains jobs across all workers even when workers create new jobs" do
    Sidekiq::Job.jobs.clear
    FirstWorker.count = 0
    SecondWorker.count = 0

    assert_equal 0, ThirdWorker.jobs.size

    assert_equal 0, FirstWorker.count
    assert_equal 0, SecondWorker.count

    ThirdWorker.perform_async

    assert_equal 1, ThirdWorker.jobs.size

    Sidekiq::Job.drain_all

    assert_equal 0, ThirdWorker.jobs.size

    assert_equal 1, FirstWorker.count
    assert_equal 1, SecondWorker.count
  end

  it "drains jobs of workers with symbolized queue names" do
    Sidekiq::Job.jobs.clear

    AltQueueWorker.perform_async(5, 6)
    assert_equal 1, AltQueueWorker.jobs.size

    Sidekiq::Job.drain_all
    assert_equal 0, AltQueueWorker.jobs.size
  end

  it "can execute a job" do
    DirectWorker.execute_job(DirectWorker.new, [2, 3])
  end

  describe "queue testing" do
    before do
      require "sidekiq/testing"
      Sidekiq::Testing.fake!
    end

    after do
      Sidekiq::Testing.disable!
      Sidekiq::Queues.clear_all
    end

    it "finds enqueued jobs" do
      assert_equal 0, Sidekiq::Queues["default"].size

      QueueWorker.perform_async(1, 2)
      QueueWorker.perform_async(1, 2)
      AltQueueWorker.perform_async(1, 2)

      assert_equal 2, Sidekiq::Queues["default"].size
      assert_equal [1, 2], Sidekiq::Queues["default"].first["args"]

      assert_equal 1, Sidekiq::Queues["alt"].size
    end

    it "clears out all queues" do
      assert_equal 0, Sidekiq::Queues["default"].size

      QueueWorker.perform_async(1, 2)
      QueueWorker.perform_async(1, 2)
      AltQueueWorker.perform_async(1, 2)

      Sidekiq::Queues.clear_all

      assert_equal 0, Sidekiq::Queues["default"].size
      assert_equal 0, QueueWorker.jobs.size
      assert_equal 0, Sidekiq::Queues["alt"].size
      assert_equal 0, AltQueueWorker.jobs.size
    end

    it "finds jobs enqueued by client" do
      Sidekiq::Client.push(
        "class" => "NonExistentWorker",
        "queue" => "missing",
        "args" => [1]
      )

      assert_equal 1, Sidekiq::Queues["missing"].size
    end

    it "respects underlying array changes" do
      # Rspec expect change() syntax saves a reference to
      # an underlying array. When the array containing jobs is
      # derived, Rspec test using `change(QueueWorker.jobs, :size).by(1)`
      # won't pass. This attempts to recreate that scenario
      # by saving a reference to the jobs array and ensuring
      # it changes properly on enqueueing
      jobs = QueueWorker.jobs
      assert_equal 0, jobs.size
      QueueWorker.perform_async(1, 2)
      assert_equal 1, jobs.size
    end
  end
end
