module Sidekiq
  class TUI
    class BaseTab
      extend Comparable

      # RM
      def self.===(other)
        self == other
      end

      def self.<=>(other)
        self.order <=> other.order
      end

      def self.to_s
        name.split("::").last
      end

      # TODO remove param, use @data
      def self.error(data)
        data[:error]
      end

      def self.render_table(tui, frame, area)
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
          selected_row: @selected_row_index,
          row_highlight_style: tui.style(fg: :white, bg: :blue),
          footer: footer
        }
        hash = defaults.merge(yield)
        hash[:block] ||= tui.block(title: hash.delete(:title), borders: :all)
        table = tui.table(**hash)
        frame.render_widget(table, area)
      end

      def self.render_stats_section(tui, frame, area)
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

      def self.selected?(entry)
        @data[:selected].index(entry.id)
      end

      # TODO Implement I18n delimiter
      def self.number_with_delimiter(number, options = {})
        precision = options[:precision] || 0
        number.round(precision)
      end

      def self.format_memory(rss_kb)
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
