require_relative "base_tab"
require_relative "set_tab"

module Sidekiq
  class TUI
    module Tabs
      class Scheduled < BaseTab
        extend SetTab

        def self.order = 4
      end
    end
  end
end
