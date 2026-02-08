require_relative "base_tab"

module Sidekiq
  class TUI
    module Tabs
      class Queues < BaseTab
        def self.order = 3

        def self.render(data, tui, frame, area)
          @data = data

          header = ["☑️", "Queue", "Size", "Latency"]
          header << "Paused?" if Sidekiq.pro?

          chunks = tui.layout_split(
            area,
            direction: :vertical,
            constraints: [
              tui.constraint_length(4), # Stats
              tui.constraint_fill(1) # Table
            ]
          )

          render_stats_section(tui, frame, chunks[0])
          render_table(tui, frame, chunks[1]) do
            {
              title: "Queues",
              header:,
              widths: header.map.with_index { |_, idx|
                tui.constraint_length((idx == 1) ? 60 : 10)
              },
              rows: @data[:queues].map.with_index { |cells, idx|
                tui.table_row(
                  cells:,
                  style: idx.even? ? nil : tui.style(bg: :dark_gray)
                )
              }
            }
          end
        end
      end
    end
  end
end
