# frozen_string_literal: true

require_relative "helper"
require "sidekiq/capsule"

describe Sidekiq::Capsule do
  before do
    @config = reset!
    @cap = @config.default_capsule
  end

  it "provides its own redis pool" do
    one = @cap
    one.concurrency = 2
    two = Sidekiq::Capsule.new("foo", @config)
    two.concurrency = 3

    # the pool is cached
    assert_equal one.redis_pool, one.redis_pool
    assert_equal two.redis_pool, two.redis_pool
    # they are sized correctly
    assert_equal 2, one.redis_pool.size
    assert_equal 3, two.redis_pool.size
    refute_equal one.redis_pool, two.redis_pool

    # they point to the same Redis
    assert one.redis { |c| c.set("hello", "world") }
    assert_equal "world", two.redis { |c| c.get("hello") }
  end

  it "parses queues correctly" do
    cap = @cap
    assert_equal ["default"], cap.queues
    assert cap.strict

    cap.queues = %w[foo bar,2]
    assert_equal %w[foo bar bar], cap.queues
    refute cap.strict

    cap.queues = ["default"]
    assert_equal %w[default], cap.queues
    assert cap.strict

    # config/sidekiq.yml input will look like this
    cap.queues = [["foo"], ["baz", 3]]
    assert_equal %w[foo baz baz baz], cap.queues
    refute cap.strict
  end
end
