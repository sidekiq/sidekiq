# frozen_string_literal: true

require_relative "helper"
require "sidekiq/api"

describe Sidekiq::IterableJobQuery do
  before { @cfg = reset! }

  def seed(jid, attrs)
    Sidekiq.redis { |c| c.hset("it-#{jid}", attrs) }
  end

  it "raises ArgumentError when given nil" do
    assert_raises(ArgumentError) { Sidekiq::IterableJobQuery.new(nil) }
  end

  it "returns nil for any jid when initialized with an empty array" do
    q = Sidekiq::IterableJobQuery.new([])
    assert_nil q["any-jid"]
  end

  it "returns nil for jids that have no iteration state" do
    q = Sidekiq::IterableJobQuery.new(["missing"])
    assert_nil q["missing"]
  end

  it "fetches iteration state and parses fields for a known jid" do
    seed("jid-1", {"ex" => "5", "rt" => "1.5", "c" => '{"offset":100}'})
    state = Sidekiq::IterableJobQuery.new(["jid-1"])["jid-1"]
    refute_nil state
    assert_equal 5, state.executions
    assert_in_delta 1.5, state.runtime, 0.0001
    assert_equal({"offset" => 100}, state.cursor)
  end

  it "exposes the cancellation marker when present" do
    seed("jid-2", {"ex" => "1", "cancelled" => "1700000000"})
    assert_equal 1_700_000_000, Sidekiq::IterableJobQuery.new(["jid-2"])["jid-2"].cancelled
  end

  it "falls back to the raw cursor string when JSON parsing fails" do
    seed("jid-3", {"c" => "not-json"})
    assert_equal "not-json", Sidekiq::IterableJobQuery.new(["jid-3"])["jid-3"].cursor
  end

  it "deduplicates and compacts the jid list" do
    seed("jid-4", {"ex" => "2"})
    q = Sidekiq::IterableJobQuery.new(["jid-4", "jid-4", nil])
    assert_equal 2, q["jid-4"].executions
  end
end
