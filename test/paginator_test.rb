# frozen_string_literal: true

require_relative "helper"
require "sidekiq/paginator"
require "securerandom"

class PaginatorHarness
  include Sidekiq::Paginator
end

describe Sidekiq::Paginator do
  before do
    reset!
    @pager = PaginatorHarness.new
  end

  # TYPE_CACHE is a process-global constant that reset! does not clear, so drop
  # the throwaway keys this test seeds to keep isolation explicit.
  after do
    Sidekiq::Paginator::TYPE_CACHE.delete_if { |key, _| key.start_with?("test:") }
  end

  def rkey(prefix)
    "test:#{prefix}:#{SecureRandom.hex(6)}"
  end

  describe "#page_items" do
    it "returns the first page with totals" do
      page, total, items = @pager.page_items((1..100).to_a, 1, 25)
      assert_equal 1, page
      assert_equal 100, total
      assert_equal (1..25).to_a, items
    end

    it "returns a later page" do
      page, total, items = @pager.page_items((1..100).to_a, 2, 25)
      assert_equal 2, page
      assert_equal 100, total
      assert_equal (26..50).to_a, items
    end

    it "normalizes a page index below 1 to the first page" do
      assert_equal 1, @pager.page_items((1..10).to_a, 0)[0]
      assert_equal 1, @pager.page_items((1..10).to_a, -5)[0]
    end

    it "resets to the first page when the index is out of range" do
      page, total, items = @pager.page_items((1..10).to_a, 100, 25)
      assert_equal 1, page
      assert_equal 10, total
      assert_equal (1..10).to_a, items
    end

    it "accepts any object that responds to to_a" do
      page, total, items = @pager.page_items(1..5, 1, 25)
      assert_equal 1, page
      assert_equal 5, total
      assert_equal (1..5).to_a, items
    end

    it "handles an empty collection" do
      assert_equal [1, 0, []], @pager.page_items([], 1, 25)
      assert_equal [1, 0, []], @pager.page_items([], 5, 25)
    end
  end

  describe "#page" do
    it "pages a sorted set with scores" do
      key = rkey("zset")
      Sidekiq.redis { |c| c.call("ZADD", key, 1, "a", 2, "b", 3, "c") }

      page, total, items = @pager.page(key, 1, 25)
      assert_equal 1, page
      assert_equal 3, total
      assert_equal [["a", 1.0], ["b", 2.0], ["c", 3.0]], items
    end

    it "pages a sorted set in reverse" do
      key = rkey("zset")
      Sidekiq.redis { |c| c.call("ZADD", key, 1, "a", 2, "b", 3, "c") }

      _, _, items = @pager.page(key, 1, 25, reverse: true)
      assert_equal [["c", 3.0], ["b", 2.0], ["a", 1.0]], items
    end

    it "pages a list" do
      key = rkey("list")
      Sidekiq.redis { |c| c.call("RPUSH", key, "x", "y", "z") }

      page, total, items = @pager.page(key, 1, 25)
      assert_equal 1, page
      assert_equal 3, total
      assert_equal %w[x y z], items
    end

    it "pages a list in reverse" do
      key = rkey("list")
      Sidekiq.redis { |c| c.call("RPUSH", key, "x", "y", "z") }

      _, _, items = @pager.page(key, 1, 25, reverse: true)
      assert_equal %w[z y x], items
    end

    it "returns an empty result for a missing key" do
      assert_equal [1, 0, []], @pager.page(rkey("missing"), 1, 25)
    end

    it "normalizes a page index below 1 to the first page" do
      key = rkey("zset")
      Sidekiq.redis { |c| c.call("ZADD", key, 1, "a") }
      assert_equal 1, @pager.page(key, 0, 25)[0]
    end
  end
end
