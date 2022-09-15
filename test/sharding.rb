# frozen_string_literal: true

require_relative "helper"
require "sidekiq"
require "sidekiq/api"

class ShardWorker
  include Sidekiq::Job
end

describe "Sharding" do
  before do
    @config = reset!
    @sh1 = Sidekiq::RedisConnection.create(size: 1, db: 6)
    @sh2 = Sidekiq::RedisConnection.create(size: 1, db: 5)
  end

  after do
    @sh1.shutdown(&:close)
    @sh2.shutdown(&:close)
  end

  describe "client" do
    it "routes jobs to the proper shard" do
      q = Sidekiq::Queue.new
      ss = Sidekiq::ScheduledSet.new
      assert_equal 0, q.size
      assert_equal 0, ss.size

      # redirect jobs with magic block
      Sidekiq::Client.via(@sh1) do
        assert_equal 0, q.size
        assert_equal 0, ss.size
        ShardWorker.perform_async
        ShardWorker.perform_in(3)
        assert_equal 1, q.size
        assert_equal 1, ss.size
      end

      Sidekiq::Client.via(@sh2) do
        assert_equal 0, ss.size
        assert_equal 0, q.size
      end

      # redirect jobs explicitly with pool attribute
      ShardWorker.set(pool: @sh2).perform_async
      ShardWorker.set(pool: @sh2).perform_in(4)
      Sidekiq::Client.via(@sh2) do
        assert_equal 1, q.size
        assert_equal 1, ss.size
      end

      assert_equal 0, ss.size
      assert_equal 0, q.size
    end
  end
end
