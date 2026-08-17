require_relative "base_tab"
require_relative "set_tab"

module Sidekiq
  class TUI
    module Tabs
      class Retries < BaseTab
        include SetTab

        def set_class = Sidekiq::RetrySet
      end
    end
  end
end
