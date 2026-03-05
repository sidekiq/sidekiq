module Sidekiq
  class TUI
    class BaseTab
      attr_reader :name

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
      GLOBAL_CONTROLS = [
        {code: "?", display: "?", description: "Help", action: ->(tab) { Tabs.show_help }},
        {code: "left", display: "←/→", description: "Select Tab", action: ->(tab) { Tabs.navigate(:left) }, refresh: true},
        {code: "right", action: ->(tab) { Tabs.navigate(:right) }, refresh: true},
        {code: "q", description: "Quit", action: ->(tab) { :quit }},
        {code: "c", modifiers: ["ctrl"], action: ->(tab) { :quit }}
      ].freeze

      SHARED_CONTROLS = {
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

      def initialize
        reset_data
        @name = self.class.name.split("::").last
      end

      def features
        []
      end

      def controls
        GLOBAL_CONTROLS + SHARED_CONTROLS.slice(*features).values.flatten
      end

      def reset_data
        @data = {selected: [], selected_row_index: 0}
      end

      def error
        @data[:error]
      end

      def error=(e)
        @data[:error] = e
      end

      def selected?(entry)
        @data[:selected].index(entry.id)
      end

      def filtering?
        false
      end

      def each_selection(unselect: true, &)
        sel = @data[:selected]
        finished = []
        if !sel.empty?
          sel.each do |id|
            yield id
            # When processing multiple items in bulk, we want to unselect
            # each row if its operation succeeds so our UI will not
            # re-process rows 1-3 if row 4 fails.
            finished << id
          end
        else
          ids = @data.dig(:table, :row_ids)
          return if !ids || ids.empty?
          yield ids[@data[:selected_row_index]]
        end
      ensure
        @data[:selected] = sel - finished if unselect
      end

      # Navigate the row selection up or down in the current tab's table.
      # @param direction [Symbol] :up or :down
      def navigate_row(direction)
        ids = @data.dig(:table, :row_ids)
        return if !ids || ids.empty?

        index_change = (direction == :down) ? 1 : -1
        @data[:selected_row_index] = (@data[:selected_row_index] + index_change) % ids.count
      end

      def prev_page
        opts = @data.dig(:table, :pager)
        return unless opts
        return if opts.page < 2

        @data[:table][:pager] = Sidekiq::TUI::PageOptions.new(opts.page - 1, opts.size)
      end

      def next_page
        np = @data.dig(:table, :next_page)
        return unless np
        opts = @data.dig(:table, :pager)
        return unless opts

        @data[:table][:pager] = Sidekiq::TUI::PageOptions.new(np, opts.size)
      end

      def toggle_select(which = :current)
        sel = @data[:selected]
        # log(which, sel)
        if which == :current
          x = @data[:table][:row_ids][@data[:selected_row_index]]
          if sel.index(x)
            # already checked, uncheck it
            sel.delete(x)
          else
            sel << x
          end
        elsif sel.empty?
          @data[:selected] = @data[:table][:row_ids]
        else
          sel.clear
        end
      end

      def refresh_data_for_stats
        stats = Sidekiq::Stats.new
        @data[:stats] = {
          processed: stats.processed,
          failed: stats.failed,
          busy: stats.workers_size,
          enqueued: stats.enqueued,
          retries: stats.retry_size,
          scheduled: stats.scheduled_size,
          dead: stats.dead_size
        }
      end

      def render_table(tui, frame, area)
        page = @data.dig(:table, :current_page) || 1
        rows = @data.dig(:table, :rows) || []
        total = @data.dig(:table, :total) || 0
        footer = ["", "Page: #{page}", "Count: #{rows.size}", "Total: #{total}"]
        footer << "Selected: #{@data[:selected].size}" unless @data[:selected].empty?

        if @data[:filter]
          @filter_style = tui.style(fg: :white, bg: :dark_gray)
          spans = [
            tui.text_span(content: "Filter: ", style: @filter_style),
            tui.text_span(content: @data[:filter], style: @filter_style)
          ]
          spans << tui.text_span(content: "_", style: tui.style(fg: :white, bg: :dark_gray, modifiers: [:slow_blink])) if @data[:filtering]
          footer << tui.text_line(spans: spans)
        end

        defaults = {
          title: "TableName",
          highlight_symbol: "➡️",
          selected_row: @data[:selected_row_index],
          row_highlight_style: tui.style(fg: :white, bg: :blue),
          footer: footer
        }
        hash = defaults.merge(yield)
        hash[:block] ||= tui.block(title: hash.delete(:title), borders: :all)
        table = tui.table(**hash)
        frame.render_widget(table, area)
      end

      def render_stats_section(tui, frame, area)
        stats = @data[:stats]

        keys = ["Processed", "Failed", "Busy", "Enqueued", "Retries", "Scheduled", "Dead"]
        values = [
          stats[:processed],
          stats[:failed],
          stats[:busy],
          stats[:enqueued],
          stats[:retries],
          stats[:scheduled],
          stats[:dead]
        ]

        # Format keys and values with spacing
        keys_line = keys.map { |k| k.to_s.ljust(12) }.join("  ")
        values_line = values.map { |v| v.to_s.ljust(12) }.join("  ")

        frame.render_widget(
          tui.paragraph(
            text: [keys_line, values_line],
            block: tui.block(title: "Statistics", borders: [:all])
          ),
          area
        )
      end

      # TODO Implement I18n delimiter
      def number_with_delimiter(number, options = {})
        precision = options[:precision] || 0
        number.round(precision)
      end

      def format_memory(rss_kb)
        return "0" if rss_kb.nil? || rss_kb == 0

        if rss_kb < 100_000
          "#{number_with_delimiter(rss_kb)} KB"
        elsif rss_kb < 10_000_000
          "#{number_with_delimiter((rss_kb / 1024.0).to_i)} MB"
        else
          "#{number_with_delimiter(rss_kb / (1024.0 * 1024.0), precision: 1)} GB"
        end
      end
    end
  end
end
