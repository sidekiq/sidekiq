require_relative "base_tab"
require_relative "set_tab"

module Sidekiq
  class TUI
    module Tabs
      class Scheduled < BaseTab
        include SetTab

        def set_class = Sidekiq::ScheduledSet
      end
    end
  end
end
