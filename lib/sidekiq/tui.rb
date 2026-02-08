require "bundler/inline"

gemfile do
  source "https://gem.coop"
  gem "ratatui_ruby", "1.3.0"
  gem "sidekiq"
end

RatatuiRuby.debug_mode!

# https://sr.ht/~kerrick/ratatui_ruby/
# https://git.sr.ht/~kerrick/ratatui_ruby/tree/stable/item/examples/
require "ratatui_ruby"
require "sidekiq/api"
require "sidekiq/paginator"

Dir[File.dirname(__FILE__) + "/tui/**/*.rb"].each { |file| require file }

# Suppress Sidekiq logger output to prevent interference with TUI rendering
require "logger"
Sidekiq.default_configuration.logger = Logger.new(IO::NULL)

DebugLogger = Logger.new("tui.log")
def log(*x)
  x.each { |item| DebugLogger.info { item } }
end

module Sidekiq
  class TUI
    include Sidekiq::Paginator

    PageOptions = Data.define(:page, :size)

    REFRESH_INTERVAL_SECONDS = 2

    TABS = Tabs.all

    # CONTROLS defines data for input handling and for displaying controls.
    # :code is the key code for input handling.
    # :display and :description are shown in the controls area, with different
    #   styling between them. If :display is omitted, :code is displayed instead.
    #   Duplicate :display and :description values are ignored, shown only once.
    # :tabs is an array of tab names where the control is active.
    # :action is a lambda to execute when the control is triggered.
    #
    # Conventions: dangerous/irreversible actions should use UPPERCASE codes.
    # The Shift button means "I'm sure".
    CONTROLS = [
      {code: "?", display: "?", description: "Help", tabs: TABS,
       action: ->(tui) { tui.show_help }},
      {code: "left", display: "←/→", description: "Select Tab", tabs: TABS,
       action: ->(tui) { tui.navigate_tab(:left) }, refresh: true},
      {code: "right", display: "←/→", description: "Select Tab", tabs: TABS,
       action: ->(tui) { tui.navigate_tab(:right) }, refresh: true},
      {code: "q", display: "q", description: "Quit", tabs: TABS,
       action: ->(tui) { :quit }},
      {code: "c", modifiers: ["ctrl"], display: "q", description: "Quit", tabs: TABS,
       action: ->(tui) { :quit }},
      {code: "h", display: "h/l", description: "Prev/Next Page", tabs: TABS - [Tabs::Home],
       action: ->(tui) { tui.prev_page }, refresh: true},
      {code: "l", display: "h/l", description: "Prev/Next Page", tabs: TABS - [Tabs::Home],
       action: ->(tui) { tui.next_page }, refresh: true},
      {code: "k", display: "j/k", description: "Prev/Next Row", tabs: TABS - [Tabs::Home],
       action: ->(tui) { tui.navigate_row(:up) }},
      {code: "j", display: "j/k", description: "Prev/Next Row", tabs: TABS - [Tabs::Home],
       action: ->(tui) { tui.navigate_row(:down) }},
      {code: "x", display: "x", description: "Select", tabs: TABS - [Tabs::Home],
       action: ->(tui) { tui.toggle_select }},
      {code: "A", modifiers: ["shift"], display: "A", description: "Select All", tabs: TABS - [Tabs::Home],
       action: ->(tui) { tui.toggle_select(:all) }},
      {code: "D", modifiers: ["shift"], display: "D", description: "Delete", tabs: [Tabs::Scheduled, Tabs::Retries, Tabs::Dead],
       action: ->(tui) { tui.alter_rows!(:delete) }, refresh: true},
      {code: "R", modifiers: ["shift"], display: "R", description: "Retry", tabs: [Tabs::Retries],
       action: ->(tui) { tui.alter_rows!(:retry) }, refresh: true},
      {code: "E", modifiers: ["shift"], display: "E", description: "Enqueue", tabs: [Tabs::Scheduled, Tabs::Dead],
       action: ->(tui) { tui.alter_rows!(:add_to_queue) }, refresh: true},
      {code: "K", modifiers: ["shift"], display: "K", description: "Kill", tabs: [Tabs::Scheduled, Tabs::Retries],
       action: ->(tui) { tui.alter_rows!(:kill) }, refresh: true},
      {code: "D", modifiers: ["shift"], display: "D", description: "Delete", tabs: [Tabs::Queues],
       action: ->(tui) { tui.delete_queue! }, refresh: true},
      {code: "p", description: "Pause/Unpause Queue", tabs: [Tabs::Queues],
       action: ->(tui) { tui.toggle_pause_queue! }},
      {code: "T", modifiers: ["shift"], description: "Terminate", tabs: [Tabs::Busy],
       action: ->(tui) { tui.terminate! }},
      {code: "Q", modifiers: ["shift"], description: "Quiet", tabs: [Tabs::Busy],
       action: ->(tui) { tui.quiet! }},
      {code: "/", display: "/", description: "Filter", tabs: [Tabs::Scheduled, Tabs::Retries, Tabs::Dead],
       action: ->(tui) { tui.start_filtering }}
    ].freeze

    def initialize
      @current_tab = Tabs::Home
      @selected_row_index = 0
      @base_style = nil
      @data = {}
      @last_refresh = Time.now
      @showing = :main
    end

    def run
      RatatuiRuby.run do |tui|
        @tui = tui
        @highlight_style = @tui.style(fg: :red, modifiers: [:underlined])
        @hotkey_style = @tui.style(modifiers: [:bold, :underlined])

        refresh_data

        loop do
          refresh_data if should_refresh?
          render
          break if handle_input == :quit
        end
      end
    end

    def render
      if @showing == :main
        @tui.draw do |frame|
          main_area, controls_area = @tui.layout_split(
            frame.area,
            direction: :vertical,
            constraints: [
              @tui.constraint_fill(1),
              @tui.constraint_length(4)
            ]
          )

          # Split main area into tabs and content
          tabs_area, content_area = @tui.layout_split(
            main_area,
            direction: :vertical,
            constraints: [
              @tui.constraint_length(3),
              @tui.constraint_fill(1)
            ]
          )

        tabs = @tui.tabs(
          titles: TABS.map(&:to_s),
          selected_index: TABS.index(@current_tab),
          block: @tui.block(title: Sidekiq::NAME, borders: [:all], title_style: @tui.style(fg: :red, modifiers: [:bold])),
          divider: " | ",
          highlight_style: @highlight_style,
          style: @base_style
        )
        frame.render_widget(tabs, tabs_area)

          render_content_area(frame, content_area)
          render_controls(frame, controls_area)
        end
      end

      if @showing == :help
        @tui.draw do |frame|
          main_area, controls_area = @tui.layout_split(
            frame.area,
            direction: :vertical,
            constraints: [
              @tui.constraint_fill(1),
              @tui.constraint_length(4)
            ]
          )
          content = @tui.block(
            title: Sidekiq::NAME,
            borders: [:all],
            title_style: @tui.style(fg: :red, modifiers: [:bold]),
            children: [
              # TODO convert to table
              @tui.paragraph(
                text: [
                  @tui.text_line(spans: ["Welcome to the Sidekiq Terminal UI"], alignment: :center),
                  @tui.text_line(spans: [
                    @tui.text_span(content: "Esc", style: @hotkey_style),
                    @tui.text_span(content: ": Close")
                  ]),
                  @tui.text_line(spans: [
                    @tui.text_span(content: "←/→", style: @hotkey_style),
                    @tui.text_span(content: ": Move between tabs")
                  ]),
                  @tui.text_line(spans: [
                    @tui.text_span(content: "j/k", style: @hotkey_style),
                    @tui.text_span(content: ": Use vim keys to move to prev/next row")
                  ]),
                  @tui.text_line(spans: [
                    @tui.text_span(content: "x", style: @hotkey_style),
                    @tui.text_span(content: ": Select/deselect current row")
                  ]),
                  @tui.text_line(spans: [
                    @tui.text_span(content: "A", style: @hotkey_style),
                    @tui.text_span(content: ": Select/deselect All visible rows")
                  ]),
                  @tui.text_line(spans: [
                    @tui.text_span(content: "h/l", style: @hotkey_style),
                    @tui.text_span(content: ": Use vim keys to move to prev/next page")
                  ]),
                  @tui.text_line(spans: [
                    @tui.text_span(content: "q", style: @hotkey_style),
                    @tui.text_span(content: ": Quit")
                  ])
                ]
              )
            ]
          )
          frame.render_widget(content, main_area)
          controls = @tui.block(
            title: "Controls",
            borders: [:all],
            children: [
              @tui.paragraph(
                text: [
                  @tui.text_line(spans: [
                    @tui.text_span(content: "Esc", style: @hotkey_style),
                    @tui.text_span(content: ": Close  ")
                  ])
                ]
              )
            ]
          )
          frame.render_widget(controls, controls_area)
        end
      end
    end

    def render_content_area(frame, content_area)
      return render_error(frame, content_area, @current_tab.error(@data)) if @current_tab.error(@data)

      @current_tab.render(@data, @tui, frame, content_area)
    end

    def render_controls(frame, area)
      keys_and_descriptions = CONTROLS
        .select { |ctrl|
          ctrl[:tabs].include?(@current_tab)
        }.map { |ctrl|
          [ctrl[:display] || ctrl[:code], ctrl[:description]]
        }.to_h

      controls = @tui.block(
        title: "Controls",
        borders: [:all],
        children: [
          @tui.paragraph(
            text: [
              @tui.text_line(spans: keys_and_descriptions.map { |key, desc|
                [
                  @tui.text_span(content: key, style: @hotkey_style),
                  @tui.text_span(content: ": #{desc}  ")
                ]
              }.flatten),
              # @tui.text_line(spans: [
              #   @tui.text_span(content: "d", style: @hotkey_style),
              #   @tui.text_span(content: ": Divider (#{@dividers[@divider_index]})  "),
              #   @tui.text_span(content: "s", style: @hotkey_style),
              #   @tui.text_span(content: ": Highlight (#{@highlight_styles[@highlight_style_index][:name]})  "),
              #   @tui.text_span(content: "b", style: @hotkey_style),
              #   @tui.text_span(content: ": Base Style (#{@base_styles[@base_style_index][:name]})  "),
              # ]),
              @tui.text_line(spans: [
                @tui.text_span(content: "Redis: #{redis_url} "),
                @tui.text_span(content: "Current Time: #{Time.now.utc}")
              ])
            ]
          )
        ]
      )
      frame.render_widget(controls, area)
    end

    def handle_input
      case @tui.poll_event
      in {type: :key, code: "backspace"} if @data[:filtering]
        @data[:filter] = @data[:filter].empty? ? "" : @data[:filter][0..-2]
      in {type: :key, code: "enter"} if @data[:filtering]
        @data[:filtering] = nil
        @data[:selected] = []
      in {type: :key, code: "esc"} if @showing == :help
        @showing = :main
      in {type: :key, code: "esc"} if @data[:filtering]
        @data[:filtering] = nil
        @data[:filter] = nil
        @data[:selected] = []
      in {type: :key, code: code} if @data[:filtering] && code.length == 1
        @data[:filter] += code
        @data[:selected] = []
      in {type: :key, code:, modifiers:}
        control = CONTROLS.find { |ctrl|
          ctrl[:code] == code &&
            (ctrl[:modifiers] || []) == (modifiers || []) &&
            ctrl[:tabs].include?(@current_tab)
        }
        return unless control
        control[:action].call(self).tap {
          refresh_data if control[:refresh]
        }
      else
        # Ignore other events
      end
    rescue => ex
      log(ex.message, ex.backtrace)
    end

    def show_help
      @showing = :help
    end

    # Navigate tabs to the left or right.
    # @param direction [Symbol] :left or :right
    def navigate_tab(direction)
      index_change = (direction == :right) ? 1 : -1
      @current_tab = TABS[(TABS.index(@current_tab) + index_change) % TABS.size]
      @selected_row_index = 0
      @data = {
        selected: [],
        filter: nil
      }
    end

    # Navigate the row selection up or down in the current tab's table.
    # @param direction [Symbol] :up or :down
    def navigate_row(direction)
      ids = @data.dig(:table, :row_ids)
      return if !ids || ids.empty?

      index_change = (direction == :down) ? 1 : -1
      @selected_row_index = (@selected_row_index + index_change) % ids.count
    end

    def start_filtering
      @data[:filtering] = true
      @data[:filter] = ""
    end

    def stop_filtering
      @data[:filtering] = false
    end

    def quiet!
      each_selection do |id|
        Sidekiq::Process.new("identity" => id).quiet!
      end
    end

    def terminate!
      each_selection do |id|
        Sidekiq::Process.new("identity" => id).stop!
      end
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
        yield ids[@selected_row_index]
      end
    ensure
      @data[:selected] = sel - finished if unselect
    end

    def delete_queue!
      each_selection do |qname|
        Sidekiq::Queue.new(qname).clear
      end
    end

    def alter_rows!(action = :add_to_queue)
      log(@current_tab.to_s, @data[:selected])
      set = case @current_tab
      when Tabs::Scheduled
        Sidekiq::ScheduledSet.new
      when Tabs::Retries
        Sidekiq::RetrySet.new
      when Tabs::Dead
        Sidekiq::DeadSet.new
      end
      return unless set
      each_selection do |id|
        score, jid = id.split("|")
        item = set.fetch(score, jid)&.first
        item&.send(action)
      end
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
      log(which, sel)
      if which == :current
        x = @data[:table][:row_ids][@selected_row_index]
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

    def toggle_pause_queue!
      return unless Sidekiq.pro?

      each_selection do |qname|
        queue = Sidekiq::Queue.new(qname)
        if queue.paused?
          queue.unpause!
        else
          queue.pause!
        end
      end
    end

    def redis_url
      Sidekiq.redis do |conn|
        conn.config.server_url
      end
    rescue
      "N/A"
    end

    def should_refresh?
      Time.now - @last_refresh >= REFRESH_INTERVAL_SECONDS
    end

    def refresh_data
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

      case @current_tab
      when Tabs::Home
        @data[:chart] ||= {
          previous_stats: {
            processed: stats.processed,
            failed: stats.failed
          },
          deltas: {
            processed: Array.new(50, 0),
            failed: Array.new(50, 0)
          }
        }

        processed_delta = stats.processed - @data[:chart][:previous_stats][:processed]
        failed_delta = stats.failed - @data[:chart][:previous_stats][:failed]

        @data[:chart][:deltas][:processed].shift
        @data[:chart][:deltas][:processed].push(processed_delta)
        @data[:chart][:deltas][:failed].shift
        @data[:chart][:deltas][:failed].push(failed_delta)

        @data[:chart][:previous_stats] = {
          processed: stats.processed,
          failed: stats.failed
        }

        redis_info = Sidekiq.default_configuration.redis_info

        @data[:redis_info] = {
          version: redis_info["redis_version"] || "N/A",
          uptime_days: redis_info["uptime_in_days"] || "N/A",
          connected_clients: redis_info["connected_clients"] || "N/A",
          used_memory: redis_info["used_memory_human"] || "N/A",
          peak_memory: redis_info["used_memory_peak_human"] || "N/A"
        }
      when Tabs::Busy
        busy = []
        table_row_ids = []

        Sidekiq::ProcessSet.new.each do |p|
          name = "#{p["hostname"]}:#{p["pid"]}"
          name += " ⭐️" if p.leader?
          name += " 🛑" if p.stopping?
          busy << [
            selected?(p) ? "✅" : "",
            name,
            Time.at(p["started_at"]).utc,
            format_memory(p["rss"].to_i),
            number_with_delimiter(p["concurrency"]),
            number_with_delimiter(p["busy"])
          ]
          table_row_ids << p.identity
        end

        @data[:busy] = busy
        @data[:table] = {row_ids: table_row_ids}
      when Tabs::Queues
        queue_summaries = Sidekiq::Stats.new.queue_summaries.sort_by(&:name)

        selected = Array(@data[:selected])
        queues = queue_summaries.map { |queue_summary|
          row_cells = [
            selected.index(queue_summary.name) ? "✅" : "",
            queue_summary.name,
            queue_summary.size.to_s,
            number_with_delimiter(queue_summary.latency, {precision: 2})
          ]
          row_cells << (queue_summary.paused? ? "✅" : "") if Sidekiq.pro?
          row_cells
        }

        table_row_ids = queue_summaries.map(&:name)

        @data[:queues] = queues
        @data[:table] = {row_ids: table_row_ids}
      when Tabs::Scheduled
        data_for_set(Sidekiq::ScheduledSet.new)
      when Tabs::Retries
        data_for_set(Sidekiq::RetrySet.new)
      when Tabs::Dead
        data_for_set(Sidekiq::DeadSet.new)
      when Tabs::Metrics
        # only need to refresh every 60 seconds
        if !@data[:metrics_refresh] || @data[:metrics_refresh] < Time.now
          q = Sidekiq::Metrics::Query.new
          query_result = q.top_jobs(minutes: 60)
          @data[:metrics] = query_result
          @data[:metrics_refresh] = Time.now + 60
        end
      end

      @last_refresh = Time.now
    rescue => e
      @data = {error: e}
    end

    def data_for_set(set)
      f = @data[:filter]
      pager, rows, current, total = if f && f.size > 2
        rows = set.scan(f).to_a
        sz = rows.size
        [Sidekiq::TUI::PageOptions.new(1, sz), rows, 1, sz]
      else
        pager = @data.dig(:table, :pager) || Sidekiq::TUI::PageOptions.new(1, 25)
        current, total, items = page(set.name, pager.page, pager.size)
        rows = items.map { |msg, score| Sidekiq::SortedEntry.new(nil, score, msg) }
        [pager, rows, current, total]
      end

      @data.merge!(
        table: {pager:, rows:, current_page: current, total:,
                next_page: (current * pager.size < total) ? pager.page + 1 : nil,
                row_ids: rows.map { |job| [job.score, job["jid"]].join("|") }}
      )
    end

    def selected?(entry)
      @data[:selected].index(entry.id)
    end

    def render_error(frame, area, err)
      log(err.message, err.backtrace)
      header = [@tui.text_line(
        spans: [@tui.text_span(content: err.message, style: @tui.style(modifiers: [:bold]))],
        alignment: :center
      )]
      lines = Array(err.backtrace).map { |line| @tui.text_line(spans: [@tui.text_span(content: line)]) }

      frame.render_widget(
        @tui.paragraph(
          text: header + lines,
          alignment: :left,
          block: @tui.block(title: "Error", borders: [:all], border_style: @tui.style(fg: :red))
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
