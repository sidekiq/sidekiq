require_relative "base_tab"
require_relative "set_tab"

module Sidekiq
  class TUI
    module Tabs
      class Dead < BaseTab
        include SetTab

        def set_class = Sidekiq::DeadSet
      end
    end
  end
end
