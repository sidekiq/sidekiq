# https://sr.ht/~kerrick/ratatui_ruby/
# https://git.sr.ht/~kerrick/ratatui_ruby/tree/stable/item/examples/
gem "ratatui_ruby", ">=1.3.0"
require "ratatui_ruby"

RatatuiRuby.debug_mode!

require "sidekiq/api"
require "sidekiq/paginator"

require_relative "tui/filtering"
require_relative "tui/controls"
require_relative "tui/tabs"

def log(*x)
  x.each { |item| Sidekiq.logger.info { item } }
end

module Sidekiq
  class TUI
    include Sidekiq::Component

    LOCALE_DIRECTORIES = [File.expand_path("#{File.dirname(__FILE__)}/../../web/locales")]
    PageOptions = Data.define(:page, :size)

    REFRESH_INTERVAL_SECONDS = 2

    def initialize
      @config = Sidekiq.default_configuration
      @base_style = nil
      @last_refresh = Time.now
      load_language
    end

    def run
      # Must log to a file, terminal is now controlled by Ratatui
      config.logger = Logger.new("tui.log")

      RatatuiRuby.run do |tui|
        @tui = tui
        @highlight_style = @tui.style(fg: :light_red, modifiers: [:underlined])
        @hotkey_style = @tui.style(modifiers: [:bold, :underlined])
        # eager load tabs
        Tabs.all(self)

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

          all_tabs = Tabs.all(self)
          tabs = @tui.tabs(
            titles: all_tabs.map { |tab| t(tab.name) },
            selected_index: all_tabs.index(Tabs.current),
            block: @tui.block(title: " #{Sidekiq::NAME} ", borders: [:all], title_style: @tui.style(fg: :light_red, modifiers: [:bold])),
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
            title: " #{Sidekiq::NAME} ",
            borders: [:all],
            title_style: @tui.style(fg: :light_red, modifiers: [:bold]),
            children: [
              # TODO convert to table
              @tui.paragraph(
                text: [
                  @tui.text_line(spans: ["Welcome to the Sidekiq Terminal UI"], alignment: :center),
                  @tui.text_line(spans: [
                    @tui.text_span(content: "Global hotkeys")
                  ]),
                  @tui.text_line(spans: []),
                  @tui.text_line(spans: [
                    @tui.text_span(content: "Esc", style: @hotkey_style),
                    @tui.text_span(content: ": Close this window")
                  ]),
                  @tui.text_line(spans: [
                    @tui.text_span(content: "←/→", style: @hotkey_style),
                    @tui.text_span(content: ": Move between tabs")
                  ]),
                  @tui.text_line(spans: [
                    @tui.text_span(content: "h/l", style: @hotkey_style),
                    @tui.text_span(content: ": Move to prev/next page of data")
                  ]),
                  @tui.text_line(spans: [
                    @tui.text_span(content: "j/k", style: @hotkey_style),
                    @tui.text_span(content: ": Move to prev/next row in current page")
                  ]),
                  @tui.text_line(spans: [
                    @tui.text_span(content: "x", style: @hotkey_style),
                    @tui.text_span(content: ": Select/deselect current row")
                  ]),
                  @tui.text_line(spans: [
                    @tui.text_span(content: "A", style: @hotkey_style),
                    @tui.text_span(content: ": Select/deselect All rows in current page")
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
            title: t("Controls"),
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
          @tui.text_span(content: ": #{t(hash[:description])}  ")
        ]
      }.flatten)

      last = active_keys[8...]
      lines << if last && last.size > 0
        @tui.text_line(spans: last.map { |hash|
          [
            @tui.text_span(content: hash[:display] || hash[:code], style: @hotkey_style),
            @tui.text_span(content: ": #{t(hash[:description])}  ")
          ]
        }.flatten)
      else
        @tui.text_line(spans: [])
      end

      footer = [
        @tui.text_span(content: "Redis: #{redis_url}    "),
        @tui.text_span(content: "#{t("Now")}: #{Time.now.utc}    "),
        @tui.text_span(content: "#{t("Locale")}: #{@lang}")
      ]

      if Tabs.current.data[:filter]
        @filter_style = @tui.style(fg: :white, bg: :dark_gray)
        footer += [
          @tui.text_span(content: "   #{t("Filter")}: ", style: @filter_style),
          @tui.text_span(content: Tabs.current.data[:filter], style: @filter_style),
          @tui.text_span(content: "_", style: @tui.style(fg: :white, bg: :dark_gray, modifiers: [:slow_blink]))
        ]
      end
      lines << @tui.text_line(spans: footer)

      controls = @tui.block(title: t("Controls"), borders: [:all],
        children: [@tui.paragraph(text: lines)])
      frame.render_widget(controls, area)
    end

    def handle_input
      case @tui.poll_event
      in {type: :key, code: "esc"} if Tabs.showing == :help
        Tabs.show_main
      in {type: :key, code: code} if Tabs.current.filtering? && code.length == 1
        Tabs.current.append_to_filter(code)
        Tabs.current.refresh_data
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
          block: @tui.block(title: t("Error"), borders: [:all], border_style: @tui.style(fg: :light_red))
        ),
        area
      )
    end

    public def t(msg, options = nil)
      string = @strings[msg] || msg
      if options.nil?
        string
      else
        string % options
      end
    end

    def load_strings(lang)
      {}.tap do |all|
        find_locale_files(lang).each do |file|
          strs = YAML.safe_load_file(file)
          all.merge! strs[lang]
        end
      end
    end

    def locale_files
      @@locale_files ||= LOCALE_DIRECTORIES.flat_map { |path|
        Dir["#{path}/*.yml"]
      }
    end

    def available_locales
      @@available_locales ||= Set.new(locale_files.map { |path| File.basename(path, ".yml") })
    end

    def find_locale_files(lang)
      locale_files.select { |file| file =~ /\/#{lang}\.yml$/ }
    end

    def load_language
      require "yaml"
      # LANG=en_US.utf-8
      lang = (ENV["LANG"] || "en").split(".").first # "en_US"
      while lang.size > 0
        hash = load_strings(lang)
        if hash.size > 0
          # found a working language dataset
          @lang = lang
          @strings = hash
          Sidekiq.logger.info { [@lang, @strings.size] }
          break
        end
        # Try "en_US", "en_U", "en_", "en"
        # It's ugly and bruteforce but it works
        lang = lang[..-2]
      end
    end
  end
end
