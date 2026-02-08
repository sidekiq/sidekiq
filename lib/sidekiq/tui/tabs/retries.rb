require_relative "base_tab"
require_relative "set_tab"

module Sidekiq
  class TUI
    module Tabs
      class Retries < BaseTab
        extend SetTab

        def self.order = 5
      end
    end
  end
end
