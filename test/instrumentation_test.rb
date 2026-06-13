# frozen_string_literal: true

require_relative "helper"
require "sidekiq/component"
require "sidekiq/launcher"
require "sidekiq/manager"
require "sidekiq/processor"

class InstrumentationThing
  include Sidekiq::Component

  attr_reader :config

  def initialize(config)
    @config = config
  end
end

describe "Sidekiq instrumentation" do
  before do
    @config = reset!
    @config.instrumentation_handlers.clear
  end

  it "has no handlers by default" do
    assert_empty @config.instrumentation_handlers
  end

  it "calls instrumentation handlers" do
    events = []
    @config.instrumentation_handlers << ->(event, payload, cfg) {
      events << [event, payload, cfg]
    }

    @config.instrument(Sidekiq::Instrumentation::SLOW_RTT, {readings: [1, 2]})

    assert_equal 1, events.size
    assert_equal Sidekiq::Instrumentation::SLOW_RTT, events[0][0]
    assert_equal({readings: [1, 2]}, events[0][1])
    assert_equal @config, events[0][2]
  end

  it "delegates through Sidekiq::Component" do
    events = []
    @config.instrumentation_handlers << ->(event, payload, _cfg) {
      events << [event, payload]
    }

    InstrumentationThing.new(@config).instrument("test.sidekiq", {foo: "bar"})

    assert_equal 1, events.size
    assert_equal ["test.sidekiq", {foo: "bar"}], events[0]
  end

  it "does not break when a handler raises" do
    output = capture_logging(@config, Logger::ERROR) do
      @config.instrumentation_handlers << ->(_event, _payload, _cfg) { raise "boom" }
      @config.instrumentation_handlers << ->(event, _payload, _cfg) { @seen = event }
      @config.instrument(Sidekiq::Instrumentation::SLOW_RTT, {})
    end

    assert_equal Sidekiq::Instrumentation::SLOW_RTT, @seen
    assert_match(/INSTRUMENTATION HANDLER THREW AN ERROR/, output)
  end

  it "publishes slow_rtt from the launcher" do
    events = []
    @config.instrumentation_handlers << ->(event, payload, _cfg) {
      events << [event, payload]
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
    assert_equal Sidekiq::Instrumentation::SLOW_RTT, events[0][0]
    assert_equal 50_000, events[0][1][:threshold]
    assert_equal 5, events[0][1][:readings].size
  ensure
    Sidekiq::Launcher::RTT_READINGS.reset
  end

  it "publishes hard_shutdown from the manager" do
    events = []
    @config.instrumentation_handlers << ->(event, payload, _cfg) {
      events << [event, payload]
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
    assert_equal Sidekiq::Instrumentation::HARD_SHUTDOWN, events[0][0]
    assert_equal 1, events[0][1][:thread_count]
    assert_equal 1, events[0][1][:job_count]
    fetcher.verify
  end

  it "publishes redis_recovered from the processor" do
    events = []
    @config.instrumentation_handlers << ->(event, payload, _cfg) {
      events << [event, payload]
    }

    capsule = @config.default_capsule
    processor = Sidekiq::Processor.new(capsule)
    processor.instance_variable_set(:@down, ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - 2.5)

    fetcher = Minitest::Mock.new
    fetcher.expect(:retrieve_work, nil)
    capsule.define_singleton_method(:fetcher) { fetcher }

    processor.send(:get_one)

    assert_equal 1, events.size
    assert_equal Sidekiq::Instrumentation::REDIS_RECOVERED, events[0][0]
    assert_operator events[0][1][:downtime], :>=, 2.0
  end
end
