# frozen_string_literal: true

require "csv"
require "sidekiq"
require_relative "../helper"

describe Sidekiq::Job::Iterable::NestedEnumerator do
  before do
    @outer_items = [1, 2]
    @inner_items = {1 => [3], 2 => [4, 5]}
  end

  it "accepts only callables as enums" do
    e = assert_raises(ArgumentError) do
      build_enumerator(outer: [[1, 2, 3].each])
    end
    assert_equal "enums must contain only procs/lambdas", e.message
  end

  it "raises when cursor is not of the same size as enums" do
    e = assert_raises(ArgumentError) do
      build_enumerator(cursor: [0])
    end
    assert_equal "cursor should have one item per enum", e.message
  end

  it "yields enumerator when called without a block" do
    enum = build_enumerator
    assert_kind_of Enumerator, enum
    assert_nil enum.size
  end

  it "yields every nested record with their cursor position" do
    enum = build_enumerator
    expected = [
      [3, [0, 0]], # in the format of [item, cursor]
      [4, [1, 0]],
      [5, [1, 1]]
    ]

    enum.each_with_index do |(item, cursor), index|
      expected_item, expected_cursor = expected[index]
      assert_equal expected_item, item
      assert_equal expected_cursor, cursor
    end
  end

  it "can be resumed" do
    expected = [
      [3, [0, 0]],
      [4, [1, 0]],
      [5, [1, 1]]
    ]

    expected.each_with_index do |(item, cursor), index|
      enum = build_enumerator(cursor: cursor)
      assert_equal [item, cursor], enum.next
      assert_equal(expected[index + 1], enum.next) if index != expected.size - 1
    end
  end

  it "does not yield anything if contains empty enum" do
    enum = ->(_item, _cursor) { [].each }
    enum = build_enumerator(inner: enum)
    assert_empty enum.to_a
  end

  it "works with single level nesting" do
    enum = build_enumerator(inner: nil)
    expected = [[1, 0], [2, 1]]

    enum.each_with_index do |(item, cursor), index|
      expected_item, expected_cursor = expected[index]
      assert_equal expected_item, item
      assert_equal [expected_cursor], cursor
    end
  end

  private

  def build_enumerator(
    outer: ->(cursor) { @outer_items.each_with_index.drop(cursor || 0) },
    inner: ->(item, cursor) { @inner_items[item].each_with_index.drop(cursor || 0) },
    cursor: nil
  )
    Sidekiq::Job::Iterable::NestedEnumerator.new([outer, inner].compact, cursor: cursor).each
  end
end
