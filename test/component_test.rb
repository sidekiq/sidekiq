# frozen_string_literal: true

require_relative "helper"
require "sidekiq/component"
require "socket"

class ComponentHarness
  include Sidekiq::Component
end

describe Sidekiq::Component do
  before { @c = ComponentHarness.new }

  describe "#real_ms" do
    it "returns the current wall-clock time in integer milliseconds" do
      now = @c.real_ms
      assert_kind_of Integer, now
      assert_in_delta(Time.now.to_f * 1000, now, 1000)
    end
  end

  describe "#mono_ms" do
    it "returns a monotonic integer that does not decrease" do
      a = @c.mono_ms
      b = @c.mono_ms
      assert_kind_of Integer, a
      assert_operator b, :>=, a
    end
  end

  describe "#tid" do
    it "returns a base-36 string and is memoized per thread" do
      first = @c.tid
      assert_kind_of String, first
      assert_match(/\A-?[0-9a-z]+\z/, first)
      assert_equal first, @c.tid
    end

    it "is independent across threads" do
      other = Thread.new { ComponentHarness.new.tid }.value
      refute_equal @c.tid, other
    end
  end

  describe "#hostname" do
    def with_env(key, value)
      original = ENV[key]
      value.nil? ? ENV.delete(key) : ENV[key] = value
      yield
    ensure
      original.nil? ? ENV.delete(key) : ENV[key] = original
    end

    it "prefers the DYNO environment variable" do
      with_env("DYNO", "web.1") do
        assert_equal "web.1", @c.hostname
      end
    end

    it "falls back to Socket.gethostname when DYNO is unset" do
      with_env("DYNO", nil) do
        assert_equal Socket.gethostname, @c.hostname
      end
    end
  end

  describe "#default_tag" do
    it "returns the basename of a regular directory" do
      assert_equal "myapp", @c.default_tag("/var/www/myapp")
    end

    it "skips the Capistrano release timestamp when under a 'releases' dir" do
      assert_equal "myapp", @c.default_tag("/var/www/myapp/releases/20231015120000")
    end

    it "returns the numeric basename when the parent is not 'releases'" do
      assert_equal "20231015120000", @c.default_tag("/var/www/myapp/builds/20231015120000")
    end

    it "returns a non-numeric basename even if the parent is 'releases'" do
      assert_equal "current", @c.default_tag("/var/www/myapp/releases/current")
    end
  end
end
