# frozen_string_literal: true

require_relative "helper"
require "sidekiq/middleware/partition"

class PartitionedJob
  include Sidekiq::Job

  sidekiq_options partition: 0

  def perform(key, *)
  end
end

class UnpartitionedJob
  include Sidekiq::Job

  def perform(*)
  end
end

describe Sidekiq::Middleware::Partition::Server do
  before do
    @config = reset!
    @mw = Sidekiq::Middleware::Partition::Server.new
    @mw.config = @config
  end

  def job_hash(klass, args, jid: "jid1", queue: "default")
    {"class" => klass.to_s, "args" => args, "jid" => jid, "queue" => queue}
  end

  def lock_value(key, queue: "default")
    @config.redis { |c| c.call("GET", "partition:#{queue}:#{key}") }
  end

  it "runs a non-partitioned job untouched" do
    ran = false
    @mw.call(UnpartitionedJob.new, job_hash(UnpartitionedJob, [1]), "default") { ran = true }
    assert ran
  end

  it "runs a partitioned job when its partition is free, holding the lock only while it runs" do
    ran = false
    @mw.call(PartitionedJob.new, job_hash(PartitionedJob, ["acct-1"]), "default") do
      ran = true
      assert_equal "jid1", lock_value("acct-1"), "lock is held during the job"
    end
    assert ran
    assert_nil lock_value("acct-1"), "lock is released after the job"
  end

  it "reschedules (does not run) a job whose partition is busy" do
    @config.redis { |c| c.call("SET", "partition:default:acct-1", "other-jid") }

    ran = false
    @mw.call(PartitionedJob.new, job_hash(PartitionedJob, ["acct-1"], jid: "jid2"), "default") { ran = true }

    refute ran, "must not run while the partition is busy"
    scheduled = @config.redis { |c| c.call("ZRANGE", "schedule", 0, -1) }
    assert_equal 1, scheduled.size
    assert_includes scheduled.first, "jid2"
    assert_includes scheduled.first, "partition_requeues"
  end

  it "lets a different partition key run while another is busy" do
    @config.redis { |c| c.call("SET", "partition:default:acct-1", "other-jid") }

    ran = false
    @mw.call(PartitionedJob.new, job_hash(PartitionedJob, ["acct-2"], jid: "jid3"), "default") { ran = true }

    assert ran, "a different partition key must not be blocked"
  end

  it "runs normally when the partition arg is missing" do
    ran = false
    @mw.call(PartitionedJob.new, job_hash(PartitionedJob, []), "default") { ran = true }
    assert ran
  end

  it "does not release a lock it no longer owns" do
    # a slow job whose lock expired and was re-acquired by another job must not delete that job's lock
    @mw.call(PartitionedJob.new, job_hash(PartitionedJob, ["acct-1"], jid: "jid1"), "default") do
      @config.redis { |c| c.call("SET", "partition:default:acct-1", "someone-else") }
    end
    assert_equal "someone-else", lock_value("acct-1")
  end
end
