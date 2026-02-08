require_relative "base_tab"
require_relative "set_tab"

module Sidekiq
  class TUI
    module Tabs
      class Dead < BaseTab
        extend SetTab

        def self.order = 6

        def self.set_class = Sidekiq::DeadSet

        def self.refresh_data
          @reset_data unless @data
          refresh_data_for_stats
          refresh_data_for_set
        end
      end
    end
  end
end
