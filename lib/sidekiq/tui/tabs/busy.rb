require_relative "base_tab"

module Sidekiq
  class TUI
    module Tabs
      class Busy < BaseTab
        def self.order = 2

        def self.render(data, tui, frame, area)
          @data = data

          chunks = tui.layout_split(
            area,
            direction: :vertical,
            constraints: [
              tui.constraint_length(4), # Stats
              tui.constraint_length(4), # Status
              tui.constraint_fill(1)   # Graph
            ]
          )

          render_stats_section(tui, frame, chunks[0])
          render_status_section(tui, frame, chunks[1])
          render_table(tui, frame, chunks[2]) do
            {
              title: "Processes",
              header: ["☑️", "Name", "Started", "RSS", "Threads", "Busy"],
              widths: [
                tui.constraint_length(5),
                tui.constraint_fill(1),
                tui.constraint_length(24),
                tui.constraint_length(10),
                tui.constraint_length(6),
                tui.constraint_length(6)
              ],
              rows: @data[:busy].map.with_index { |cells, idx|
                tui.table_row(
                  cells:,
                  style: idx.even? ? nil : tui.style(bg: :dark_gray)
                )
              }
            }
          end
        end

        def self.render_status_section(tui, frame, area)
          keys = ["Processes", "Threads", "Busy", "Utilization", "RSS"]
          values = []
          processes = Sidekiq::ProcessSet.new
          workset = Sidekiq::WorkSet.new
          ws = workset.size
          values << (s = processes.size
                    number_with_delimiter(s))
          values << (x = processes.total_concurrency
                    number_with_delimiter(x))
          values << number_with_delimiter(ws)
          values << "#{(x == 0) ? 0 : ((ws / x.to_f) * 100).round(0)}%"
          values << format_memory(processes.total_rss)

          keys_line = keys.map { |k| k.to_s.ljust(12) }.join("  ")
          values_line = values.map { |v| v.to_s.ljust(12) }.join("  ")

          frame.render_widget(
            tui.paragraph(
              text: [keys_line, values_line],
              block: tui.block(title: "Status", borders: [:all])
            ),
            area
          )
        end
      end
    end
  end
end
