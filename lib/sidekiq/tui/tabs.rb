module Sidekiq
  class TUI
    module Tabs
      def self.all
        @all ||= BaseTab.subclasses.map(&:new).sort
      end

      def self.current
        @current ||= all.find { |tab| tab.is_a?(Tabs::Home) }
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
