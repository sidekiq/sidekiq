module Sidekiq
  class TUI
    module Tabs
      def self.all = BaseTab.subclasses.sort_by(&:order)
    end
  end
end
