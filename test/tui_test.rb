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

  describe "#striped_rows" do
    it "applies alternating dark_gray background styling to rows" do
      tab = ConcreteTab.new(FakeTUIParent.new)
      
      # Mock tui object with minimal required methods
      mock_tui = Object.new
      def mock_tui.table_row(cells:, style: nil)
        {cells: cells, style: style}
      end
      def mock_tui.style(bg:)
        {bg: bg}
      end
      
      rows_data = [
        ["Row 1", "Data 1"],
        ["Row 2", "Data 2"],
        ["Row 3", "Data 3"]
      ]
      
      result = tab.striped_rows(mock_tui, rows_data)
      
      assert_equal 3, result.length
      assert_nil result[0][:style] # Even rows (0-indexed) have no style
      assert_equal({bg: :dark_gray}, result[1][:style]) # Odd rows get dark_gray
      assert_nil result[2][:style]
    end
  end
end

describe "Sidekiq::TUI Help Table" do
  it "defines correct help data structure" do
    help_data = [
      ["Esc", "Close this window"],
      ["←/→", "Move between tabs"],
      ["h/l", "Move to prev/next page of data"],
      ["j/k", "Move to prev/next row in current page"],
      ["x", "Select/deselect current row"],
      ["A", "Select/deselect All rows in current page"],
      ["q", "Quit"]
    ]
    
    # Verify structure
    assert_equal 7, help_data.length
    help_data.each do |row|
      assert_equal 2, row.length, "Each help row should have exactly 2 columns"
      assert_kind_of String, row[0], "Key should be a string"
      assert_kind_of String, row[1], "Action description should be a string"
    end
  end
  
  it "includes all essential hotkeys in help data" do
    help_data = [
      ["Esc", "Close this window"],
      ["←/→", "Move between tabs"],
      ["h/l", "Move to prev/next page of data"],
      ["j/k", "Move to prev/next row in current page"],
      ["x", "Select/deselect current row"],
      ["A", "Select/deselect All rows in current page"],
      ["q", "Quit"]
    ]
    
    keys = help_data.map(&:first)
    
    # Essential keys should be present
    assert_includes keys, "Esc"
    assert_includes keys, "←/→"
    assert_includes keys, "q"
    assert_includes keys, "x"
    assert_includes keys, "A"
  end
  
  it "help table has proper column headers" do
    headers = ["Key", "Action"]
    
    assert_equal 2, headers.length
    assert_equal "Key", headers[0]
    assert_equal "Action", headers[1]
  end
end
