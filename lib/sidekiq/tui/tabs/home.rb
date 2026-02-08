require_relative "base_tab"

module Sidekiq
  class TUI
    module Tabs
      class Home < BaseTab
        def self.order = 1

        def self.render(data, tui, frame, area)
          @data = data

          chunks = tui.layout_split(
            area,
            direction: :vertical,
            constraints: [
              tui.constraint_length(4), # Stats
              tui.constraint_fill(1),   # Graph
              tui.constraint_length(4) # Redis
            ]
          )

          render_stats_section(tui, frame, chunks[0])
          render_chart_section(tui, frame, chunks[1])
          render_redis_info_section(tui, frame, chunks[2])
        end

        def self.render_chart_section(tui, frame, area)
          max_value = [@data[:chart][:deltas][:processed].max, @data[:chart][:deltas][:failed].max, 1].max
          y_max = [max_value, 5].max

          processed_data = @data[:chart][:deltas][:processed].each_with_index.map { |value, idx| [idx.to_f, value.to_f] }
          failed_data = @data[:chart][:deltas][:failed].each_with_index.map { |value, idx| [idx.to_f, value.to_f] }

          datasets = [
            tui.dataset(
              name: "",
              data: processed_data,
              style: tui.style(fg: :green),
              marker: :dot,
              graph_type: :line
            ),
            tui.dataset(
              name: "",
              data: failed_data,
              style: tui.style(fg: :red),
              marker: :dot,
              graph_type: :line
            )
          ]

          num_labels = 5
          y_labels = (0...num_labels).map do |i|
            value = ((y_max * i) / (num_labels - 1)).round
            value.to_s
          end

          beacon_pulse = (Time.now.to_i % 2 == 0) ? "●" : " "

          chart = tui.chart(
            datasets: datasets,
            x_axis: tui.axis(
              bounds: [0.0, 49.0],
              labels: [],
              style: tui.style(fg: :white)
            ),
            y_axis: tui.axis(
              bounds: [0.0, y_max.to_f],
              labels: y_labels,
              style: tui.style(fg: :white)
            ),
            block: tui.block(
              title: "Dashboard #{beacon_pulse}",
              borders: [:all]
            )
          )

          frame.render_widget(chart, area)
        end

        def self.render_redis_info_section(tui, frame, area)
          redis_info = @data[:redis_info]

          uptime_value = (redis_info[:uptime_days] == "N/A") ? "N/A" : "#{redis_info[:uptime_days]} days"

          keys = ["Version", "Uptime", "Connected Clients", "Memory Usage", "Peak Memory"]
          values = [
            redis_info[:version].to_s,
            uptime_value,
            redis_info[:connected_clients].to_s,
            redis_info[:used_memory].to_s,
            redis_info[:peak_memory].to_s
          ]

          # Format keys and values with spacing
          keys_line = keys.map { |k| k.ljust(18) }.join("  ")
          values_line = values.map { |v| v.ljust(18) }.join("  ")

          frame.render_widget(
            tui.paragraph(
              text: [keys_line, values_line],
              block: tui.block(title: "Redis Information", borders: [:all])
            ),
            area
          )
        end
      end
    end
  end
end
