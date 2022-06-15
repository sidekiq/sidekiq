# frozen_string_literal: true

require_relative "helper"
require "sidekiq/fetch"
require "sidekiq/api"

describe Sidekiq::BasicFetch do
  before do
    @config = reset!
    @config.redis do |conn|
      conn.rpush("queue:basic", "msg")
    end
  end

  def fetcher(options)
    @config.merge!(options)
    Sidekiq::BasicFetch.new(@config)
  end

  it "retrieves" do
    fetch = fetcher(queues: ["basic", "bar"])
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
    fetch = fetcher(queues: ["basic", "bar", "bar"], strict: true)
    cmd = fetch.queues_cmd
    assert_equal cmd, ["queue:basic", "queue:bar", Sidekiq::BasicFetch::TIMEOUT]
  end

  it "bulk requeues" do
    @config.redis do |conn|
      conn.rpush("queue:foo", ["bob", "bar"])
      conn.rpush("queue:bar", "widget")
    end

    q1 = Sidekiq::Queue.new("foo")
    q2 = Sidekiq::Queue.new("bar")
    assert_equal 2, q1.size
    assert_equal 1, q2.size

    fetch = fetcher(queues: ["foo", "bar"])
    works = 3.times.map { fetch.retrieve_work }
    assert_equal 0, q1.size
    assert_equal 0, q2.size

    fetch.bulk_requeue(works, {queues: []})
    assert_equal 2, q1.size
    assert_equal 1, q2.size
  end

  it "sleeps when no queues are active" do
    fetch = fetcher(queues: [])
    mock = Minitest::Mock.new
    mock.expect(:call, nil, [Sidekiq::BasicFetch::TIMEOUT])
    fetch.stub(:sleep, mock) { assert_nil fetch.retrieve_work }
    mock.verify
  end
end
