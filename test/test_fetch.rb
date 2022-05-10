# frozen_string_literal: true

require_relative "helper"
require "sidekiq/fetch"
require "sidekiq/api"

describe Sidekiq::BasicFetch do
  before do
    @prev_redis = Sidekiq.instance_variable_get(:@redis) || {}
    Sidekiq.redis do |conn|
      conn.flushdb
      conn.rpush("queue:basic", "msg")
    end
  end

  after do
    Sidekiq.redis = @prev_redis
  end

  it "retrieves" do
    fetch = Sidekiq::BasicFetch.new(queues: ["basic", "bar"])
    uow = fetch.retrieve_work
    refute_nil uow
    assert_equal "basic", uow.queue_name
    assert_equal "msg", uow.job
    q = Sidekiq::Queue.new("basic")
    assert_equal 0, q.size
    uow.requeue
    assert_equal 1, q.size
    assert_nil uow.acknowledge
  end

  it "retrieves with strict setting" do
    fetch = Sidekiq::BasicFetch.new(queues: ["basic", "bar", "bar"], strict: true)
    cmd = fetch.queues_cmd
    assert_equal cmd, ["queue:basic", "queue:bar", Sidekiq::BasicFetch::TIMEOUT]
  end

  it "bulk requeues" do
    Sidekiq.redis do |conn|
      conn.rpush("queue:foo", ["bob", "bar"])
      conn.rpush("queue:bar", "widget")
    end

    q1 = Sidekiq::Queue.new("foo")
    q2 = Sidekiq::Queue.new("bar")
    assert_equal 2, q1.size
    assert_equal 1, q2.size

    fetch = Sidekiq::BasicFetch.new(queues: ["foo", "bar"])
    works = 3.times.map { fetch.retrieve_work }
    assert_equal 0, q1.size
    assert_equal 0, q2.size

    fetch.bulk_requeue(works, {queues: []})
    assert_equal 2, q1.size
    assert_equal 1, q2.size
  end

  it "sleeps when no queues are active" do
    fetch = Sidekiq::BasicFetch.new(queues: [])
    mock = Minitest::Mock.new
    mock.expect(:call, nil, [Sidekiq::BasicFetch::TIMEOUT])
    fetch.stub(:sleep, mock) { assert_nil fetch.retrieve_work }
    mock.verify
  end
end
