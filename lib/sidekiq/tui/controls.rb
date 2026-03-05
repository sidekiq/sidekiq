module Sidekiq
  class TUI
    module Controls

      # Defines data for input handling and for displaying controls.
      # :code is the key code for input handling.
      # :display and :description are shown in the controls area, with different
      #   styling between them. If :display is omitted, :code is displayed instead.
      #   Duplicate :display and :description values are ignored, shown only once.
      # :tabs is an array of tab names where the control is active.
      # :action is a lambda to execute when the control is triggered.
      #
      # Conventions: dangerous/irreversible actions should use UPPERCASE codes.
      # The Shift button means "I'm sure".
      GLOBAL = [
        {code: "?", display: "?", description: "Help", action: ->(tab) { Tabs.show_help }},
        {code: "left", display: "←/→", description: "Select Tab", action: ->(tab) { Tabs.navigate(:left) }, refresh: true},
        {code: "right", action: ->(tab) { Tabs.navigate(:right) }, refresh: true},
        {code: "q", description: "Quit", action: ->(tab) { :quit }},
        {code: "c", modifiers: ["ctrl"], action: ->(tab) { :quit }}
      ].freeze

      SHARED = {
        pageable: [
          {code: "h", display: "h/l", description: "Prev/Next Page",
           action: ->(tab) { tab.prev_page }, refresh: true},
          {code: "l", action: ->(tab) { tab.next_page }, refresh: true}
        ],
        selectable: [
          {code: "k", display: "j/k", description: "Prev/Next Row",
           action: ->(tab) { tab.navigate_row(:up) }},
          {code: "j", action: ->(tab) { tab.navigate_row(:down) }},
          {code: "x", description: "Select", action: ->(tab) { tab.toggle_select }},
          {code: "A", modifiers: ["shift"], display: "A", description: "Select All",
           action: ->(tab) { tab.toggle_select(:all) }}
        ],
        filterable: [
          {code: "/", display: "/", description: "Filter", action: ->(tab) { tab.start_filtering }},
          {code: "backspace", action: ->(tab) { tab.remove_last_char_from_filter }},
          {code: "enter", action: ->(tab) { tab.stop_filtering }},
          {code: "esc", action: ->(tab) { tab.stop_and_clear_filtering }}
        ]
      }.freeze

      # Returns an array of symbols for functionality which this tab implements
      def features
        []
      end

      def controls
        GLOBAL + SHARED.slice(*features).values.flatten
      end
    end
  end
end