# frozen_string_literal: true
require_relative 'helper'
require 'sidekiq/redis_iterator'

class TestRedisIterator < Sidekiq::Test

  class Helper
    include Sidekiq::RedisIterator
  end

  describe '.sscan' do
    before do
      50.times do |i|
        Sidekiq.redis { |conn| conn.sadd('processes', "test-process-#{i}") }
      end
    end
    it 'returns identical to smembers' do
      sscan = Sidekiq.redis { |c| Helper.new.sscan(c, 'processes') }.sort!
      smembers = Sidekiq.redis { |c| c.smembers('processes') }.sort!
      assert_equal sscan.size, 50
      assert_equal sscan, smembers
    end
  end
end
