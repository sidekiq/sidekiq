# https://sr.ht/~kerrick/ratatui_ruby/
# https://git.sr.ht/~kerrick/ratatui_ruby/tree/stable/item/examples/
gem "ratatui_ruby", ">=1.3.0"
require "ratatui_ruby"

RatatuiRuby.debug_mode!

require "sidekiq/api"
require "sidekiq/paginator"

require_relative "tui/tabs"

def log(*x)
  x.each { |item| Sidekiq.logger.info { item } }
end

module Sidekiq
  class TUI
    include Sidekiq::Component

    PageOptions = Data.define(:page, :size)

    REFRESH_INTERVAL_SECONDS = 2

    def initialize
      @config = Sidekiq.default_configuration
      @base_style = nil
      @last_refresh = Time.now
    end

    def run
      # Must log to a file, terminal is now controlled by Ratatui
      config.logger = Logger.new("tui.log")

      RatatuiRuby.run do |tui|
        @tui = tui
        @highlight_style = @tui.style(fg: :light_red, modifiers: [:underlined])
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
      if Tabs.showing == :main
        @tui.draw do |frame|
          main_area, controls_area = @tui.layout_split(
            frame.area,
            direction: :vertical,
            constraints: [
              @tui.constraint_fill(1),
              @tui.constraint_length(5)
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
            titles: Tabs.all.map(&:name),
            selected_index: Tabs.all.index(Tabs.current),
            block: @tui.block(title: Sidekiq::NAME, borders: [:all], title_style: @tui.style(fg: :light_red, modifiers: [:bold])),
            divider: " | ",
            highlight_style: @highlight_style,
            style: @base_style
          )
          frame.render_widget(tabs, tabs_area)

          render_content_area(frame, content_area)
          render_controls(frame, controls_area)
        end
      end

      if Tabs.showing == :help
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
            title_style: @tui.style(fg: :light_red, modifiers: [:bold]),
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
      return render_error(frame, content_area, Tabs.current.error) if Tabs.current.error

      Tabs.current.render(@tui, frame, content_area)
    end

    def render_controls(frame, area)
      active_keys = Tabs.current.controls.filter { |hash| hash[:description] }

      # Split controls into two lines, 8 is arbitrary
      # TODO Dynamically split based on term width?
      first = active_keys[...8]
      lines = []
      lines << @tui.text_line(spans: first.map { |hash|
        [
          @tui.text_span(content: hash[:display] || hash[:code], style: @hotkey_style),
          @tui.text_span(content: ": #{hash[:description]}  ")
        ]
      }.flatten)

      last = active_keys[8...]
      lines << if last && last.size > 0
        @tui.text_line(spans: last.map { |hash|
          [
            @tui.text_span(content: hash[:display] || hash[:code], style: @hotkey_style),
            @tui.text_span(content: ": #{hash[:description]}  ")
          ]
        }.flatten)
      else
        @tui.text_line(spans: [])
      end

      lines << @tui.text_line(spans: [
        @tui.text_span(content: "Redis: #{redis_url}    "),
        @tui.text_span(content: "Current Time: #{Time.now.utc}")
      ])

      controls = @tui.block(title: "Controls", borders: [:all],
        children: [@tui.paragraph(text: lines)])
      frame.render_widget(controls, area)
    end

    def handle_input
      case @tui.poll_event
      in {type: :key, code: "esc"} if Tabs.showing == :help
        Tabs.show_main
      in {type: :key, code: code} if Tabs.current.filtering? && code.length == 1
        Tabs.current.append_to_filter(code)
      in {type: :key, code:, modifiers:}
        tab = Tabs.current
        control = tab.controls.find { |ctrl|
          ctrl[:code] == code &&
            (ctrl[:modifiers] || []) == (modifiers || [])
        }
        return unless control
        control[:action].call(Tabs.current).tap {
          refresh_data if control[:refresh]
        }
      else
        # Ignore other events
      end
    rescue => ex
      log(ex.message, ex.backtrace)
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
      Tabs.current.refresh_data
      @last_refresh = Time.now
    rescue => e
      handle_exception(e)
      Tabs.current.error = e
    end

    def render_error(frame, area, err)
      header = [@tui.text_line(
        spans: [@tui.text_span(content: err.message, style: @tui.style(modifiers: [:bold]))],
        alignment: :center
      )]
      lines = Array(err.backtrace).map { |line| @tui.text_line(spans: [@tui.text_span(content: line)]) }

      frame.render_widget(
        @tui.paragraph(
          text: header + lines,
          alignment: :left,
          block: @tui.block(title: "Error", borders: [:all], border_style: @tui.style(fg: :light_red))
        ),
        area
      )
    end
  end
end
