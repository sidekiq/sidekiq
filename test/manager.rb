# frozen_string_literal: true

require_relative "helper"
require "sidekiq/manager"

describe Sidekiq::Manager do
  before do
    @config = reset!
    @cap = Sidekiq::Capsule.new("default", @config)
    @config.capsules << @cap
  end

  def new_manager
    Sidekiq::Manager.new(@cap)
  end

  it "creates N processor instances" do
    mgr = new_manager
    assert_equal @cap.concurrency, mgr.workers.size
  end

  it "shuts down the system" do
    mgr = new_manager
    mgr.start
    mgr.stop(::Process.clock_gettime(::Process::CLOCK_MONOTONIC))
  end

  it "throws away dead processors" do
    mgr = new_manager
    init_size = mgr.workers.size
    processor = mgr.workers.first
    begin
      mgr.processor_result(processor, "ignored")

      assert_equal init_size, mgr.workers.size
      refute mgr.workers.include?(processor)
    ensure
      mgr.quiet
    end
  end
end
