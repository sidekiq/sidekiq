# frozen_string_literal: true

require_relative "helper"
require "sidekiq/ring_buffer"

describe Sidekiq::RingBuffer do
  it "fills with the default value of zero" do
    rb = Sidekiq::RingBuffer.new(3)
    assert_equal [0, 0, 0], rb.to_a
    assert_equal 3, rb.size
  end

  it "fills with a custom default value" do
    rb = Sidekiq::RingBuffer.new(3, 7)
    assert_equal [7, 7, 7], rb.to_a
  end

  it "returns the element that was pushed" do
    rb = Sidekiq::RingBuffer.new(3)
    assert_equal 42, (rb << 42)
  end

  it "fills slots in order before wrapping" do
    rb = Sidekiq::RingBuffer.new(3)
    rb << 1
    rb << 2
    assert_equal [1, 2, 0], rb.buffer
  end

  it "overwrites the oldest slot once full" do
    rb = Sidekiq::RingBuffer.new(3)
    [1, 2, 3, 4].each { |n| rb << n }
    # index 0 (holding 1) is overwritten by 4; 2 and 3 remain
    assert_equal [4, 2, 3], rb.buffer
  end

  it "exactly fills the buffer at capacity" do
    rb = Sidekiq::RingBuffer.new(3)
    [1, 2, 3].each { |n| rb << n }
    assert_equal [1, 2, 3], rb.buffer
  end

  it "wraps repeatedly for more than two full cycles" do
    rb = Sidekiq::RingBuffer.new(3)
    (1..7).each { |n| rb << n }
    # slot 0: 1,4,7 -> 7; slot 1: 2,5 -> 5; slot 2: 3,6 -> 6
    assert_equal [7, 5, 6], rb.buffer
  end

  it "delegates [] to the underlying buffer" do
    rb = Sidekiq::RingBuffer.new(3)
    rb << 10
    rb << 20
    assert_equal 10, rb[0]
    assert_equal 20, rb[1]
    assert_equal 0, rb[2]
  end

  it "supports Enumerable methods" do
    rb = Sidekiq::RingBuffer.new(3)
    [1, 2, 3].each { |n| rb << n }
    assert_equal [2, 4, 6], rb.map { |n| n * 2 }
    assert_equal 6, rb.sum
  end

  it "exposes the underlying buffer" do
    rb = Sidekiq::RingBuffer.new(2)
    assert_equal [0, 0], rb.buffer
  end

  it "resets to the default value" do
    rb = Sidekiq::RingBuffer.new(3)
    [1, 2, 3].each { |n| rb << n }
    rb.reset
    assert_equal [0, 0, 0], rb.buffer
  end

  it "resets to a custom value" do
    rb = Sidekiq::RingBuffer.new(3)
    [1, 2, 3].each { |n| rb << n }
    rb.reset(9)
    assert_equal [9, 9, 9], rb.buffer
  end

  it "keeps writing to the correct slot after a reset" do
    rb = Sidekiq::RingBuffer.new(3)
    [1, 2, 3, 4].each { |n| rb << n }
    rb.reset
    rb << 99
    # @index continued from 4, so 99 lands in slot 4 % 3 == 1
    assert_equal [0, 99, 0], rb.buffer
  end
end
