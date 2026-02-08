require_relative "base_tab"
require_relative "set_tab"

module Sidekiq
  class TUI
    module Tabs
      class Dead < BaseTab
        extend SetTab

        def self.order = 6
      end
    end
  end
end
