require_relative "tabs/home"
require_relative "tabs/busy"
require_relative "tabs/queues"
require_relative "tabs/scheduled"
require_relative "tabs/retries"
require_relative "tabs/dead"
require_relative "tabs/metrics"

module Sidekiq
  class TUI
    module Tabs
      Set = Set.new([Home, Busy, Queues, Scheduled, Retries, Dead, Metrics])

      def self.all
        @all ||= Set.map(&:new)
      end

      def self.current
        @current ||= all.first
      end

      # Navigate tabs to the left or right.
      # @param direction [Symbol] :left or :right
      def self.navigate(direction)
        index_change = (direction == :right) ? 1 : -1
        @current = all[(all.index(current) + index_change) % all.size]
        current.reset_data
      end

      def self.showing
        @showing ||= :main
      end

      def self.show_main
        @showing = :main
      end

      def self.show_help
        @showing = :help
      end
    end
  end
end
