# frozen_string_literal: true

require_relative "helper"
require "sidekiq/api"

class ApiUtilsHarness
  include Sidekiq::ApiUtils
end

describe Sidekiq::ApiUtils do
  before do
    @util = ApiUtilsHarness.new
  end

  describe "#calculate_latency" do
    it "returns 0.0 when no timestamp is present" do
      assert_equal 0.0, @util.calculate_latency({})
    end

    it "computes latency from an integer millisecond timestamp" do
      now_ms = (Time.now.to_f * 1000).to_i
      assert_in_delta 5.0, @util.calculate_latency("enqueued_at" => now_ms - 5000), 0.5
    end

    it "computes latency from a legacy float (epoch seconds) timestamp" do
      assert_in_delta 5.0, @util.calculate_latency("enqueued_at" => Time.now.to_f - 5), 0.5
    end

    it "prefers enqueued_at over created_at" do
      now_ms = (Time.now.to_f * 1000).to_i
      latency = @util.calculate_latency("enqueued_at" => now_ms - 2000, "created_at" => now_ms - 9000)
      assert_in_delta 2.0, latency, 0.5
    end

    it "falls back to created_at when enqueued_at is absent" do
      now_ms = (Time.now.to_f * 1000).to_i
      assert_in_delta 3.0, @util.calculate_latency("created_at" => now_ms - 3000), 0.5
    end
  end
end
