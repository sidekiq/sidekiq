# frozen_string_literal: true

module Sidekiq
  class Rails
    module Warnings
      ##
      # Forwards Sidekiq operational warnings to ActiveSupport::Notifications.
      # Loaded only when Sidekiq runs inside Rails.
      #
      #   ActiveSupport::Notifications.subscribe("slow_rtt.sidekiq") do |*args|
      #     event = ActiveSupport::Notifications::Event.new(*args)
      #     ...
      #   end
      #
      class ActiveSupportBridge
        def call(name, payload, _cfg = nil)
          ::ActiveSupport::Notifications.instrument(name, payload)
        end
      end
    end
  end
end
