module Sidekiq
  class TUI
    class BaseTab
      include Controls

      attr_reader :name
      attr_reader :data

      def initialize(parent)
        @parent = parent
        @name = self.class.name.split("::").last
        reset_data
      end

      def t(*)
        @parent.t(*)
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

        defaults = {
          title: "TableName",
          footer: footer
        }
        if features.include?(:selectable)
          defaults.merge!({
            highlight_symbol: "➡️",
            selected_row: @data[:selected_row_index],
            row_highlight_style: tui.style(fg: :white, bg: :blue)
          })
        end
        hash = defaults.merge(yield)
        hash[:block] ||= tui.block(title: hash.delete(:title), borders: :all)
        table = tui.table(**hash)
        frame.render_widget(table, area)
      end

      def render_stats_section(tui, frame, area)
        stats = @data[:stats]
        keys = ["Processed", "Failed", "Busy", "Enqueued", "Retries", "Scheduled", "Dead"]
        values = %i[processed failed busy enqueued retries scheduled dead].map { |k| number_with_delimiter(stats[k]) }
        render_kv_section(tui, frame, area, title: "Statistics", keys:, values:)
      end

      # Render a bordered paragraph with a line of (translated) keys over
      # a line of preformatted values, each column ljust'ed to +width+.
      def render_kv_section(tui, frame, area, title:, keys:, values:, width: 12)
        keys_line = keys.map { |k| t(k).to_s.ljust(width) }.join("  ")
        values_line = values.map { |v| v.to_s.ljust(width) }.join("  ")

        frame.render_widget(
          tui.paragraph(
            text: [keys_line, values_line],
            block: tui.block(title:, borders: [:all])
          ),
          area
        )
      end

      # Split a tab's area into the standard stats header and a fill
      # area for the tab's main content.
      def stats_content_split(tui, area)
        tui.layout_split(
          area,
          direction: :vertical,
          constraints: [
            tui.constraint_length(4), # Stats
            tui.constraint_fill(1) # Content
          ]
        )
      end

      def striped_rows(tui, rows)
        rows.map.with_index { |cells, idx|
          tui.table_row(
            cells:,
            style: idx.even? ? nil : tui.style(bg: :dark_gray)
          )
        }
      end

      def chart_y_axis(tui, y_max, num_labels: 5)
        labels = (0...num_labels).map { |i| ((y_max * i) / (num_labels - 1)).round.to_s }
        tui.axis(
          bounds: [0.0, y_max.to_f],
          labels: labels,
          style: tui.style(fg: :white)
        )
      end

      # [thousands_separator, decimal_separator] per locale.
      # Locales not listed here use the English default [",", "."].
      NUMERIC_SEPARATORS = {
        # period thousands, comma decimal
        "da" => [".", ","], "de" => [".", ","], "el" => [".", ","],
        "es" => [".", ","], "it" => [".", ","], "nl" => [".", ","],
        "pt" => [".", ","], "pt-BR" => [".", ","], "tr" => [".", ","],
        "vi" => [".", ","],
        # space thousands, comma decimal
        "cs" => [" ", ","], "fr" => [" ", ","], "lt" => [" ", ","],
        "nb" => [" ", ","], "pl" => [" ", ","], "ru" => [" ", ","],
        "sv" => [" ", ","], "uk" => [" ", ","]
      }.freeze

      def number_with_delimiter(number, options = {})
        precision = options[:precision] || 0
        rounded = number.round(precision)
        thousands, decimal = NUMERIC_SEPARATORS.fetch(@parent.lang, [",", "."])
        integer_part, decimal_part = rounded.to_s.split(".")
        integer_with_sep = integer_part.gsub(/(\d)(?=(\d{3})+(?!\d))/, "\\1#{thousands}")
        (precision > 0) ? "#{integer_with_sep}#{decimal}#{(decimal_part || "").ljust(precision, "0")}" : integer_with_sep
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
