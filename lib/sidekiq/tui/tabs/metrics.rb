require_relative "base_tab"

module Sidekiq
  class TUI
    module Tabs
      class Metrics < BaseTab
        COLORS = %i[blue cyan yellow red green white gray]

        def self.order = 7

        def self.render(data, tui, frame, area)
          @data = data

          chunks = tui.layout_split(
            area,
            direction: :vertical,
            constraints: [
              tui.constraint_length(4), # Stats
              tui.constraint_fill(1) # Chart
              # TOOD Table
            ]
          )

          render_stats_section(tui, frame, chunks[0])
          render_metrics_chart(tui, frame, chunks[1])
        end

        # Run to generate metrics data:
        #   cd myapp && bundle install
        #   bundle exec rake seed_jobs
        #   bundle exec sidekiq
        def self.render_metrics_chart(tui, frame, area)
          y_max = 5
          csize = COLORS.size
          q = @data[:metrics]
          job_results = q.job_results.sort_by { |(kls, jr)| jr.totals["s"] }.reverse.first(COLORS.size)
          # visible_kls = job_results.first(5).map(&:first)
          # chart_data = {
          #   series: job_results.map { |(kls, jr)| [kls, jr.dig("series", "s")] }.to_h,
          #   marks: query_result.marks.map { |m| [m.bucket, m.label] },
          #   starts_at: query_result.starts_at.iso8601,
          #   ends_at: query_result.ends_at.iso8601,
          #   visibleKls: visible_kls,
          #   yLabel: 'TotalExecutionTime',
          #   units: 'seconds',
          #   markLabel: '*',
          # }

          datasets = job_results.map.with_index do |(kls, data), idx|
            # log kls, data, idx
            hrdata = data.dig("series", "s")
            tm = Time.now
            tmi = tm.to_i
            tm = Time.at(tmi - (tmi % 60)).utc
            data = Array.new(60) { |idx| idx }.map do |bucket_idx|
              jumpback = bucket_idx * 60
              value = hrdata[(tm - jumpback).iso8601] || 0
              y_max = value if value > y_max
              # we have 60 data points, newest data should be
              # at highest indexes so we have to rejigger the index
              # here
              [59 - bucket_idx, value]
            end
            # log data

            log(data)
            tui.dataset(name: kls,
              data: data,
              style: tui.style(fg: COLORS[idx % csize]),
              marker: :dot,
              graph_type: :line)
          end

          num_labels = 5
          y_labels = (0...num_labels).map do |i|
            value = ((y_max * i) / (num_labels - 1)).round
            value.to_s
          end
          xlabels = [
            q.starts_at.iso8601[11..15],
            q.ends_at.iso8601[11..15]
          ]

          # beacon_pulse = (Time.now.to_i % 2 == 0) ? "●" : " "

          chart = tui.chart(
            datasets: datasets,
            x_axis: tui.axis(
              bounds: [0.0, 60.0],
              labels: xlabels,
              style: tui.style(fg: :white)
            ),
            y_axis: tui.axis(
              bounds: [0.0, y_max.to_f],
              labels: y_labels,
              style: tui.style(fg: :white)
            ),
            block: tui.block(
              title: "Metrics",
              borders: [:all]
            )
          )

          frame.render_widget(chart, area)
        end
      end
    end
  end
end
