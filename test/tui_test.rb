# frozen_string_literal: true

require_relative "helper"

# Load TUI internals without pulling in ratatui_ruby (which is a :tui group gem)
module Sidekiq
  class TUI
  end
end
require "sidekiq/tui/controls"
require "sidekiq/tui/tabs/base_tab"

class FakeTUIParent
  attr_reader :lang

  def initialize(lang = "en")
    @lang = lang
  end

  def t(key) = key.to_s
end

class ConcreteTab < Sidekiq::TUI::BaseTab
  def refresh_data
  end
end

# Minimal stand-in that captures the args passed to the underlying TUI calls
# so we can assert the structure of what BaseTab renders.
class CapturingTUI
  attr_reader :axis_args, :table_rows

  def initialize
    @table_rows = []
  end

  def axis(**kwargs)
    @axis_args = kwargs
  end

  def table_row(cells:, style:)
    row = {cells: cells, style: style}
    @table_rows << row
    row
  end

  def style(**kw)
    kw
  end
end

describe "Sidekiq::TUI::BaseTab" do
  describe "#number_with_delimiter" do
    it "returns small numbers as strings without modification" do
      tab = ConcreteTab.new(FakeTUIParent.new)
      assert_equal "0", tab.number_with_delimiter(0)
      assert_equal "999", tab.number_with_delimiter(999)
    end

    it "inserts comma separators for thousands in English locale" do
      tab = ConcreteTab.new(FakeTUIParent.new("en"))
      assert_equal "1,000", tab.number_with_delimiter(1_000)
      assert_equal "1,234,567", tab.number_with_delimiter(1_234_567)
      assert_equal "1,500,000,000", tab.number_with_delimiter(1_500_000_000)
    end

    it "rounds and formats decimal numbers with precision in English locale" do
      tab = ConcreteTab.new(FakeTUIParent.new("en"))
      assert_equal "15.68", tab.number_with_delimiter(15.678, precision: 2)
      assert_equal "1,234.50", tab.number_with_delimiter(1234.5, precision: 2)
      assert_equal "3,932.00", tab.number_with_delimiter(3932.0, precision: 2)
    end

    it "uses period thousands separator and comma decimal for German locale" do
      tab = ConcreteTab.new(FakeTUIParent.new("de"))
      assert_equal "1.234.567", tab.number_with_delimiter(1_234_567)
      assert_equal "1.234,50", tab.number_with_delimiter(1234.5, precision: 2)
    end

    it "uses space thousands separator and comma decimal for French locale" do
      tab = ConcreteTab.new(FakeTUIParent.new("fr"))
      assert_equal "1 234 567", tab.number_with_delimiter(1_234_567)
      assert_equal "1 234,50", tab.number_with_delimiter(1234.5, precision: 2)
    end

    it "falls back to English separators for locales not in the map" do
      tab = ConcreteTab.new(FakeTUIParent.new("ja"))
      assert_equal "1,234,567", tab.number_with_delimiter(1_234_567)
    end
  end

  describe "#format_memory" do
    it "returns 0 for nil or zero rss" do
      tab = ConcreteTab.new(FakeTUIParent.new)
      assert_equal "0", tab.format_memory(nil)
      assert_equal "0", tab.format_memory(0)
    end

    it "formats values under 100_000 KB as KB with delimiter" do
      tab = ConcreteTab.new(FakeTUIParent.new)
      assert_equal "512 KB", tab.format_memory(512)
      assert_equal "99,999 KB", tab.format_memory(99_999)
    end

    it "converts values between 100_000 and 10_000_000 KB to MB" do
      tab = ConcreteTab.new(FakeTUIParent.new)
      assert_equal "100 MB", tab.format_memory(102_400)
    end

    it "converts values over 10_000_000 KB to GB with one decimal" do
      tab = ConcreteTab.new(FakeTUIParent.new)
      assert_match(/\d+\.\d GB/, tab.format_memory(11_000_000))
    end

    it "uses locale-aware separators in memory formatting" do
      tab = ConcreteTab.new(FakeTUIParent.new("de"))
      assert_equal "99.999 KB", tab.format_memory(99_999)
    end
  end

  describe "#chart_y_axis" do
    it "emits evenly-spaced integer labels from 0 to y_max" do
      tab = ConcreteTab.new(FakeTUIParent.new)
      tui = CapturingTUI.new

      tab.chart_y_axis(tui, 100, num_labels: 5)

      assert_equal ["0", "25", "50", "75", "100"], tui.axis_args[:labels]
      assert_equal [0.0, 100.0], tui.axis_args[:bounds]
    end

    it "scales the labels to the requested count" do
      tab = ConcreteTab.new(FakeTUIParent.new)
      tui = CapturingTUI.new

      tab.chart_y_axis(tui, 200, num_labels: 3)

      assert_equal ["0", "100", "200"], tui.axis_args[:labels]
    end

    it "emits all-zero labels when y_max is 0 (avoids divide-by-zero on an empty chart)" do
      tab = ConcreteTab.new(FakeTUIParent.new)
      tui = CapturingTUI.new

      tab.chart_y_axis(tui, 0, num_labels: 4)

      assert_equal ["0", "0", "0", "0"], tui.axis_args[:labels]
    end
  end

  describe "#striped_rows" do
    it "alternates background style: nil for even-indexed rows, dark_gray for odd" do
      tab = ConcreteTab.new(FakeTUIParent.new)
      tui = CapturingTUI.new

      out = tab.striped_rows(tui, [["a", "b"], ["c", "d"], ["e", "f"]])

      assert_equal 3, out.size
      assert_nil out[0][:style]
      assert_equal({bg: :dark_gray}, out[1][:style])
      assert_nil out[2][:style]
      assert_equal ["a", "b"], out[0][:cells]
    end
  end
end
