module Sidekiq
  class TUI
    module Tabs
      module SetTab
        def render(data, tui, frame, area)
          @data = data

          chunks = tui.layout_split(
            area,
            direction: :vertical,
            constraints: [
              tui.constraint_length(4), # Stats
              tui.constraint_fill(1)   # Table
            ]
          )

          render_stats_section(tui, frame, chunks[0])
          render_table(tui, frame, chunks[1]) do
            {
              title: @current_tab,
              header: ["☑️", "When", "Queue", "Job", "Arguments"],
              widths: [
                tui.constraint_length(5),
                tui.constraint_length(24),
                tui.constraint_length(20),
                tui.constraint_length(30),
                tui.constraint_fill(1)
              ]
            }.tap do |h|
              rows = @data[:table][:rows].map.with_index { |entry, idx|
                tui.table_row(
                  cells: [
                    selected?(entry) ? "✅" : "",
                    entry.at,
                    entry.queue,
                    entry.display_class,
                    entry.display_args
                  ],
                  style: idx.even? ? nil : tui.style(bg: :dark_gray)
                )
              }
              h[:rows] = rows
            end
          end
        end
      end
    end
  end
end
