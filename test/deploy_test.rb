# frozen_string_literal: true

require_relative "helper"
require "sidekiq/deploy"

describe Sidekiq::Deploy do
  before do
    @config = reset!
    @deploy = Sidekiq::Deploy.new(@config.redis_pool)
  end

  it "records a deploy mark keyed by the minute-floored timestamp" do
    at = Time.utc(2026, 5, 29, 10, 15, 30)
    @deploy.mark!(at: at, label: "abc123 fix the thing")

    assert_equal({"2026-05-29T10:15:00Z" => "abc123 fix the thing"}, @deploy.fetch(at.to_date))
  end

  it "rolls up multiple marks within the same minute into a single entry" do
    at = Time.utc(2026, 5, 29, 10, 15, 30)
    @deploy.mark!(at: at, label: "first")
    @deploy.mark!(at: at + 20, label: "first")  # same label, same minute: locked out
    @deploy.mark!(at: at + 25, label: "second") # different label, same minute: stamp already set

    marks = @deploy.fetch(at.to_date)
    assert_equal 1, marks.size
    assert_equal "first", marks["2026-05-29T10:15:00Z"]
  end

  it "records separate entries for marks in different minutes" do
    at = Time.utc(2026, 5, 29, 10, 15, 30)
    @deploy.mark!(at: at, label: "first")
    @deploy.mark!(at: at + 60, label: "second")

    marks = @deploy.fetch(at.to_date)
    assert_equal 2, marks.size
    assert_equal "first", marks["2026-05-29T10:15:00Z"]
    assert_equal "second", marks["2026-05-29T10:16:00Z"]
  end

  it "returns an empty hash when there are no marks for the date" do
    assert_empty @deploy.fetch(Time.utc(2000, 1, 1).to_date)
  end

  it "falls back to the git-derived label when none is given" do
    at = Time.utc(2026, 5, 29, 12, 0, 0)
    expected = Sidekiq::Deploy::LABEL_MAKER.call
    @deploy.mark!(at: at)

    assert_equal({"2026-05-29T12:00:00Z" => expected}, @deploy.fetch(at.to_date))
  end
end
