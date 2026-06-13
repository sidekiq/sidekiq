# frozen_string_literal: true

module Sidekiq
  ##
  # Sidekiq publishes operational events for subscribers to monitor.
  # Sidekiq Pro and Enterprise publish additional events using the same API.
  #
  #   Sidekiq.configure_server do |config|
  #     config.instrumentation_handlers << ->(event, payload, _cfg) do
  #       puts "#{event} #{payload.inspect}"
  #     end
  #   end
  #
  module Instrumentation
    SLOW_RTT = "slow_rtt.sidekiq"
    SLOW_ITERATION = "slow_iteration.sidekiq"
    REDIS_EVICTION_POLICY = "redis_eviction_policy.sidekiq"
    HARD_SHUTDOWN = "hard_shutdown.sidekiq"
    REDIS_RECOVERED = "redis_recovered.sidekiq"
  end
end
