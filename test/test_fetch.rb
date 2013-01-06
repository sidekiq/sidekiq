require 'helper'
require 'sidekiq/fetch'

class TestFetcher < MiniTest::Unit::TestCase

  def setup
    Sidekiq.redis do |conn|
      conn.del('queue:basic')
      conn.rpush('queue:basic', 'msg')
    end
  end

  def test_basic_fetch_retrieve
    fetch = Sidekiq::BasicFetch.new(:queues => ['basic', 'bar'])
    uow = fetch.retrieve_work
    refute_nil uow
    assert_equal 'basic', uow.queue_name
    assert_equal 'msg', uow.message
    q = Sidekiq::Queue.new('basic')
    assert_equal 0, q.size
    uow.requeue
    assert_equal 1, q.size
    assert_nil uow.acknowledge
  end

  def test_basic_fetch_strict_retrieve
    fetch = Sidekiq::BasicFetch.new(:queues => ['basic', 'bar', 'bar'], :strict => true)
    cmd = fetch.queues_cmd
    assert_equal cmd, ['queue:basic', 'queue:bar', 1]
  end
end
