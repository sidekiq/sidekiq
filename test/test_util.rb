require 'helper'
require 'sidekiq/util'

class TestUtil < Sidekiq::Test
  class UtilClass
    include Sidekiq::Util
  end

  describe 'util' do
    before do
      @orig_redis = Sidekiq.redis_pool
      Sidekiq.redis = REDIS
      Sidekiq.redis { |conn| conn.flushdb }
    end

    after do
      Sidekiq.redis = @orig_redis
    end

    # In real code that manages the hash sets for process keys
    # sets their expiration time to 60 seconds, so processes
    # who don't have a set under their name are considered 'dead'
    # because they haven't reported in
    describe '#cleanup_dead_process_records' do
      before do
        # Set up some live and dead processes
        @live_members = ['localhost-123', 'localhost-125']
        @dead_members = ['localhost-124']

        Sidekiq.redis do |conn|
          conn.sadd('processes', @live_members + @dead_members)
          # Add Heartbeats for the live processes
          @live_members.each do |m|
            conn.hset(m, 'beat', Time.now.to_f)
          end
        end

        @util = UtilClass.new
      end

      after do
        Sidekiq.redis do |conn|
          conn.srem('processes', @live_members + @dead_members)
          @live_members.each do |m|
            conn.hdel(m, 'beat')
          end
        end
      end

      it "should remove dead process records" do
        assert_equal 3, Sidekiq.redis{ |r| r.scard('processes') }
        @util.cleanup_dead_process_records
        still_alive = Sidekiq.redis{|r| r.smembers('processes')}
        assert_equal still_alive.sort, @live_members.sort
      end
    end
  end
end
