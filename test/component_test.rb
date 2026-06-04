# frozen_string_literal: true

require_relative "helper"

describe Sidekiq::Component do
  before do
    # Sidekiq::Component is a mixin that only depends on an @config being present.
    host = Class.new do
      include Sidekiq::Component

      def initialize(config)
        @config = config
      end
    end
    @comp = host.new(Sidekiq::Config.new)
  end

  describe "#default_tag" do
    it "uses the basename of the given directory" do
      assert_equal "myapp", @comp.default_tag("/var/www/myapp")
    end

    it "resolves through a Capistrano numeric release dir to the app name" do
      # .../myapp/releases/<timestamp> should tag as "myapp", not the timestamp
      assert_equal "myapp", @comp.default_tag("/var/www/myapp/releases/20240101120000")
    end

    it "keeps a non-numeric leaf even under a releases dir" do
      assert_equal "current", @comp.default_tag("/var/www/myapp/releases/current")
    end

    it "keeps a numeric basename when its parent is not a releases dir" do
      assert_equal "2024", @comp.default_tag("/srv/2024")
    end
  end

  describe "#hostname" do
    it "prefers the DYNO env var when present" do
      prev = ENV["DYNO"]
      ENV["DYNO"] = "web.1"
      assert_equal "web.1", @comp.hostname
    ensure
      prev.nil? ? ENV.delete("DYNO") : (ENV["DYNO"] = prev)
    end

    it "falls back to the socket hostname without DYNO" do
      prev = ENV["DYNO"]
      ENV.delete("DYNO")
      assert_equal Socket.gethostname, @comp.hostname
    ensure
      ENV["DYNO"] = prev unless prev.nil?
    end
  end

  describe "#tid" do
    before { Thread.current["sidekiq_tid"] = nil }
    after { Thread.current["sidekiq_tid"] = nil }

    it "is the object_id XOR pid in base36" do
      expected = (Thread.current.object_id ^ ::Process.pid).to_s(36)
      assert_equal expected, @comp.tid
    end

    it "is memoized per thread" do
      assert_equal @comp.tid, @comp.tid
    end
  end

  describe "#process_nonce and #identity" do
    it "produces a 12-char hex nonce" do
      assert_match(/\A[0-9a-f]{12}\z/, @comp.process_nonce)
    end

    it "memoizes the nonce" do
      assert_equal @comp.process_nonce, @comp.process_nonce
    end

    it "builds identity as hostname:pid:nonce" do
      assert_equal "#{@comp.hostname}:#{::Process.pid}:#{@comp.process_nonce}", @comp.identity
    end
  end

  describe "clock helpers" do
    it "returns integer epoch milliseconds from real_ms" do
      assert_kind_of Integer, @comp.real_ms
      assert_operator @comp.real_ms, :>, 0
    end

    it "returns integer monotonic milliseconds from mono_ms" do
      assert_kind_of Integer, @comp.mono_ms
    end
  end
end
