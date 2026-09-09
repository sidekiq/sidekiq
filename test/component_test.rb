# frozen_string_literal: true

require_relative "helper"

describe Sidekiq::Component do
  before do
    @config = Sidekiq::Config.new
    @config.logger = NULL_LOGGER
  end

  # Minimal class that mixes in the module under test.
  def component(config = @config)
    Class.new do
      include Sidekiq::Component

      def initialize(cfg)
        @config = cfg
      end
    end.new(config)
  end

  describe "clocks" do
    it "#real_ms returns integer epoch milliseconds" do
      ms = component.real_ms
      assert_kind_of Integer, ms
      assert_operator ms, :>, 1_600_000_000_000
    end

    it "#mono_ms returns a non-decreasing integer" do
      c = component
      first = c.mono_ms
      second = c.mono_ms
      assert_kind_of Integer, first
      assert_operator second, :>=, first
    end
  end

  describe "#tid" do
    it "is a base36 string" do
      assert_match(/\A[0-9a-z]+\z/, component.tid)
    end

    it "is memoized per thread" do
      c = component
      assert_equal c.tid, c.tid
    end
  end

  describe "#hostname" do
    it "prefers the DYNO environment variable" do
      old = ENV["DYNO"]
      ENV["DYNO"] = "web.1"
      begin
        assert_equal "web.1", component.hostname
      ensure
        old.nil? ? ENV.delete("DYNO") : ENV["DYNO"] = old
      end
    end

    it "falls back to Socket.gethostname" do
      old = ENV.delete("DYNO")
      begin
        assert_equal Socket.gethostname, component.hostname
      ensure
        ENV["DYNO"] = old if old
      end
    end
  end

  describe "identity" do
    it "#process_nonce is 12 hex characters and stable" do
      c = component
      assert_match(/\A\h{12}\z/, c.process_nonce)
      assert_equal c.process_nonce, c.process_nonce
    end

    it "#identity is host:pid:nonce" do
      c = component
      assert_equal "#{c.hostname}:#{Process.pid}:#{c.process_nonce}", c.identity
    end
  end

  describe "#default_tag" do
    it "returns the basename of the given directory" do
      assert_equal "myapp", component.default_tag("/apps/myapp")
    end

    it "returns the enclosing app name for a Capistrano releases path" do
      assert_equal "myapp", component.default_tag("/apps/myapp/releases/20240101120000")
    end

    it "returns the basename when a numeric dir is not under releases" do
      assert_equal "20240101120000", component.default_tag("/apps/myapp/20240101120000")
    end
  end

  describe "#watchdog" do
    it "returns the block's value" do
      assert_equal 42, component.watchdog("ctx") { 42 }
    end

    it "reports the exception and re-raises" do
      seen = []
      @config.error_handlers << ->(ex, ctx, _cfg) { seen << [ex, ctx] }
      c = component
      err = assert_raises(RuntimeError) do
        c.watchdog("last words") { raise "boom" }
      end
      assert_equal "boom", err.message
      assert_equal 1, seen.size
      assert_equal "last words", seen.dig(0, 1, :context)
    end
  end

  describe "#safe_thread" do
    it "names the thread and runs the block" do
      ran = Queue.new
      t = component.safe_thread("worker") { ran << Thread.current.name }
      assert_equal "sidekiq.worker", ran.pop
      t.join
    end

    it "uses the default thread priority" do
      t = component.safe_thread("worker") { sleep 0.01 }
      assert_equal Sidekiq::DEFAULT_THREAD_PRIORITY, t.priority
      t.join
    end

    it "honors config.thread_priority" do
      @config.thread_priority = 0
      t = component.safe_thread("worker") { sleep 0.01 }
      assert_equal 0, t.priority
      t.join
    end

    it "honors an explicit priority argument" do
      t = component.safe_thread("worker", priority: -3) { sleep 0.01 }
      assert_equal(-3, t.priority)
      t.join
    end
  end

  describe "#fire_event" do
    it "invokes every registered block for the event" do
      calls = []
      @config[:lifecycle_events][:startup] << -> { calls << :a }
      @config[:lifecycle_events][:startup] << -> { calls << :b }
      component.fire_event(:startup)
      assert_equal %i[a b], calls
    end

    it "invokes blocks in reverse order when reverse: true" do
      calls = []
      @config[:lifecycle_events][:shutdown] << -> { calls << :a }
      @config[:lifecycle_events][:shutdown] << -> { calls << :b }
      component.fire_event(:shutdown, reverse: true)
      assert_equal %i[b a], calls
    end

    it "clears the event after a oneshot firing" do
      count = 0
      @config[:lifecycle_events][:startup] << -> { count += 1 }
      c = component
      c.fire_event(:startup)
      c.fire_event(:startup)
      assert_equal 1, count
      assert_empty @config[:lifecycle_events][:startup]
    end

    it "keeps the event for later firings when oneshot: false" do
      count = 0
      @config[:lifecycle_events][:heartbeat] << -> { count += 1 }
      c = component
      c.fire_event(:heartbeat, oneshot: false)
      c.fire_event(:heartbeat, oneshot: false)
      assert_equal 2, count
    end

    it "reports an error from one block and continues with the rest" do
      seen = []
      @config.error_handlers << ->(ex, ctx, _cfg) { seen << ctx[:event] }
      calls = []
      @config[:lifecycle_events][:startup] << -> { raise "nope" }
      @config[:lifecycle_events][:startup] << -> { calls << :ran }
      component.fire_event(:startup)
      assert_equal %i[ran], calls
      assert_equal [:startup], seen
    end

    it "re-raises a block error immediately when reraise: true" do
      @config[:lifecycle_events][:startup] << -> { raise "stop" }
      err = assert_raises(RuntimeError) do
        component.fire_event(:startup, reraise: true)
      end
      assert_equal "stop", err.message
    end
  end

  describe "delegation to config" do
    it "#logger returns the config logger" do
      assert_same @config.logger, component.logger
    end
  end

  describe "#inspect" do
    it "produces a compact representation" do
      assert_match(/\A#<.* @config=/, component.inspect)
    end
  end
end
