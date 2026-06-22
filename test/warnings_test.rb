# frozen_string_literal: true

require_relative "helper"
require "sidekiq/component"
require "sidekiq/launcher"
require "sidekiq/manager"
require "sidekiq/processor"

class WarningThing
  include Sidekiq::Component

  attr_reader :config

  def initialize(config)
    @config = config
  end
end

describe "Sidekiq warnings" do
  before do
    @config = reset!
    @config.warning_handlers.clear
  end

  it "has no handlers by default" do
    assert_empty @config.warning_handlers
  end

  it "calls warning handlers" do
    events = []
    @config.warning_handlers << ->(name, payload, cfg) {
      events << [name, payload, cfg]
    }

    @config.fire_warning("slow_rtt.sidekiq", {readings: [1, 2]})

    assert_equal 1, events.size
    assert_equal "slow_rtt.sidekiq", events[0][0]
    assert_equal({readings: [1, 2]}, events[0][1])
    assert_equal @config, events[0][2]
  end

  it "delegates through Sidekiq::Component" do
    events = []
    @config.warning_handlers << ->(name, payload, _cfg) {
      events << [name, payload]
    }

    WarningThing.new(@config).fire_warning("test.sidekiq", {foo: "bar"})

    assert_equal 1, events.size
    assert_equal ["test.sidekiq", {foo: "bar"}], events[0]
  end

  it "does not break when a handler raises" do
    output = capture_logging(@config, Logger::ERROR) do
      @config.warning_handlers << ->(_name, _payload, _cfg) { raise "boom" }
      @config.warning_handlers << ->(name, _payload, _cfg) { @seen = name }
      @config.fire_warning("slow_rtt.sidekiq", {})
    end

    assert_equal "slow_rtt.sidekiq", @seen
    assert_match(/WARNING HANDLER THREW AN ERROR/, output)
  end

  it "publishes slow_rtt from the launcher" do
    events = []
    @config.warning_handlers << ->(name, payload, _cfg) {
      events << [name, payload]
    }

    launcher = Sidekiq::Launcher.new(@config)
    readings = Sidekiq::Launcher::RTT_READINGS
    readings.reset
    4.times { readings << 60_000 }

    conn = Object.new
    def conn.ping
    end

    clock = [0, 60_000]
    launcher.stub(:redis, ->(&block) { block.call(conn) }) do
      Process.stub(:clock_gettime, ->(_clock, unit = nil) {
        raise "unexpected unit" unless unit == :microsecond
        clock.shift || 60_000
      }) do
        launcher.send(:check_rtt)
      end
    end

    assert_equal 1, events.size
    assert_equal "slow_rtt.sidekiq", events[0][0]
    assert_equal 50_000, events[0][1][:threshold]
    assert_equal 5, events[0][1][:readings].size
  ensure
    Sidekiq::Launcher::RTT_READINGS.reset
  end

  it "publishes hard_shutdown from the manager" do
    events = []
    @config.warning_handlers << ->(name, payload, _cfg) {
      events << [name, payload]
    }

    capsule = @config.default_capsule
    fetcher = Minitest::Mock.new
    fetcher.expect(:bulk_requeue, nil, [Array])
    capsule.define_singleton_method(:fetcher) { fetcher }

    manager = Sidekiq::Manager.new(capsule)
    processor = Struct.new(:job).new({"jid" => "123"})
    def processor.kill
    end
    manager.instance_variable_set(:@workers, Set.new([processor]))
    manager.stub(:wait_for, nil) do
      manager.send(:hard_shutdown)
    end

    assert_equal 1, events.size
    assert_equal "hard_shutdown.sidekiq", events[0][0]
    assert_equal 1, events[0][1][:thread_count]
    assert_equal 1, events[0][1][:job_count]
    fetcher.verify
  end

  it "publishes redis_recovered from the processor" do
    events = []
    @config.warning_handlers << ->(name, payload, _cfg) {
      events << [name, payload]
    }

    capsule = @config.default_capsule
    processor = Sidekiq::Processor.new(capsule)
    processor.instance_variable_set(:@down, ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - 2.5)

    fetcher = Minitest::Mock.new
    fetcher.expect(:retrieve_work, nil)
    capsule.define_singleton_method(:fetcher) { fetcher }

    processor.send(:get_one)

    assert_equal 1, events.size
    assert_equal "redis_recovered.sidekiq", events[0][0]
    assert_operator events[0][1][:downtime], :>=, 2.0
  end
end
