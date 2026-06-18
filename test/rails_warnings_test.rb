# frozen_string_literal: true

require_relative "helper"
require "sidekiq/rails/warnings"

describe "Sidekiq::Rails warnings" do
  it "forwards warnings through ActiveSupportBridge" do
    received = []
    subscriber = ActiveSupport::Notifications.subscribe("slow_rtt.sidekiq") do |*args|
      received << ActiveSupport::Notifications::Event.new(*args)
    end

    bridge = Sidekiq::Rails::Warnings::ActiveSupportBridge.new
    bridge.call("slow_rtt.sidekiq", {readings: [1]})

    assert_equal 1, received.size
    assert_equal [1], received[0].payload[:readings]
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end
end
