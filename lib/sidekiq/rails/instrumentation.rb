# frozen_string_literal: true

module Sidekiq
  class Rails
    module Instrumentation
      ##
      # Forwards Sidekiq instrumentation events to ActiveSupport::Notifications.
      # Loaded only when Sidekiq runs inside Rails.
      #
      #   ActiveSupport::Notifications.subscribe("slow_rtt.sidekiq") do |*args|
      #     event = ActiveSupport::Notifications::Event.new(*args)
      #     ...
      #   end
      #
      class ActiveSupportBridge
        def call(event, payload, _cfg = nil)
          ::ActiveSupport::Notifications.instrument(event, payload)
        end
      end
    end
  end
end
