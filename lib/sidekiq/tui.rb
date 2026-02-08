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
       action: ->(tui) { tui.current_tab.prev_page }, refresh: true},
      {code: "l", display: "h/l", description: "Prev/Next Page", tabs: TABS - [Tabs::Home],
       action: ->(tui) { tui.current_tab.next_page }, refresh: true},
      {code: "k", display: "j/k", description: "Prev/Next Row", tabs: TABS - [Tabs::Home],
       action: ->(tui) { tui.current_tab.navigate_row(:up) }},
      {code: "j", display: "j/k", description: "Prev/Next Row", tabs: TABS - [Tabs::Home],
       action: ->(tui) { tui.current_tab.navigate_row(:down) }},
      {code: "x", display: "x", description: "Select", tabs: TABS - [Tabs::Home],
       action: ->(tui) { tui.current_tab.toggle_select }},
      {code: "A", modifiers: ["shift"], display: "A", description: "Select All", tabs: TABS - [Tabs::Home],
       action: ->(tui) { tui.current_tab.toggle_select(:all) }},
      {code: "D", modifiers: ["shift"], display: "D", description: "Delete", tabs: [Tabs::Scheduled, Tabs::Retries, Tabs::Dead],
       action: ->(tui) { tui.current_tab.alter_rows!(:delete) }, refresh: true},
      {code: "R", modifiers: ["shift"], display: "R", description: "Retry", tabs: [Tabs::Retries],
       action: ->(tui) { tui.current_tab.alter_rows!(:retry) }, refresh: true},
      {code: "E", modifiers: ["shift"], display: "E", description: "Enqueue", tabs: [Tabs::Scheduled, Tabs::Dead],
       action: ->(tui) { tui.current_tab.alter_rows!(:add_to_queue) }, refresh: true},
      {code: "K", modifiers: ["shift"], display: "K", description: "Kill", tabs: [Tabs::Scheduled, Tabs::Retries],
       action: ->(tui) { tui.current_tab.alter_rows!(:kill) }, refresh: true},
      {code: "D", modifiers: ["shift"], display: "D", description: "Delete", tabs: [Tabs::Queues],
       action: ->(tui) { tui.current_tab.delete_queue! }, refresh: true},
      {code: "p", description: "Pause/Unpause Queue", tabs: [Tabs::Queues],
       action: ->(tui) { tui.current_tab.toggle_pause_queue! }},
      {code: "T", modifiers: ["shift"], description: "Terminate", tabs: [Tabs::Busy],
       action: ->(tui) { tui.current_tab.terminate! }},
      {code: "Q", modifiers: ["shift"], description: "Quiet", tabs: [Tabs::Busy],
       action: ->(tui) { tui.current_tab.quiet! }},
      {code: "/", display: "/", description: "Filter", tabs: [Tabs::Scheduled, Tabs::Retries, Tabs::Dead],
       action: ->(tui) { tui.current_tab.start_filtering }}
    ].freeze

    attr_reader :current_tab

    def initialize
      @current_tab = Tabs::Home
      @base_style = nil
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
      return render_error(frame, content_area, @current_tab.error) if @current_tab.error

      @current_tab.render(@tui, frame, content_area)
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
      in {type: :key, code: "backspace"} if @current_tab.respond_to?(:filtering) && @current_tab.filtering?
        @current_tab.filter = @current_tab.filter.empty? ? "" : @current_tab.filter[0..-2]
      in {type: :key, code: "enter"} if @current_tab.respond_to?(:filtering) && @current_tab.filtering?
        @current_tab.stop_filtering
        @current_tab.reset_selected
      in {type: :key, code: "esc"} if @showing == :help
        @showing = :main
      in {type: :key, code: "esc"} if @current_tab.respond_to?(:filtering) && @current_tab.filtering?
        @current_tab.stop_filtering
        @current_tab.filter = nil
        @current_tab.reset_selected
      in {type: :key, code: code} if @current_tab.respond_to?(:filtering) && @current_tab.filtering? && code.length == 1
        @current_tab.filter += code
        @current_tab.reset_selected
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
      @current_tab.reset_data
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
      @current_tab.refresh_data
      @last_refresh = Time.now
    rescue => e
      @current_tab.error = e
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
  end
end
