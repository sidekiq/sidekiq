# frozen_string_literal: true

require_relative "helper"
require "sidekiq/rails/instrumentation"

describe "Sidekiq::Rails instrumentation" do
  it "forwards events through ActiveSupportBridge" do
    received = []
    subscriber = ActiveSupport::Notifications.subscribe(Sidekiq::Instrumentation::SLOW_RTT) do |*args|
      received << ActiveSupport::Notifications::Event.new(*args)
    end

    bridge = Sidekiq::Rails::Instrumentation::ActiveSupportBridge.new
    bridge.call(Sidekiq::Instrumentation::SLOW_RTT, {readings: [1]})

    assert_equal 1, received.size
    assert_equal [1], received[0].payload[:readings]
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end
end
