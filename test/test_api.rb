require 'helper'

class TestApi < MiniTest::Unit::TestCase
  describe 'with an empty database' do
    before do
      Sidekiq.redis {|c| c.flushdb }
    end

    it 'shows queue as empty' do
      q = Sidekiq::Queue.new
      assert_equal 0, q.size
    end

    class ApiWorker
      include Sidekiq::Worker
    end

    it 'can enumerate jobs' do
      q = Sidekiq::Queue.new
      ApiWorker.perform_async(1, 'mike')
      assert_equal ['TestApi::ApiWorker'], q.map(&:klass)

      job = q.first
      assert_equal 24, job.jid.size
      assert_equal [1, 'mike'], job.args

      q = Sidekiq::Queue.new('other')
      assert_equal 0, q.size
    end

    it 'can delete jobs' do
      q = Sidekiq::Queue.new
      ApiWorker.perform_async(1, 'mike')
      assert_equal 1, q.size
      assert_equal [true], q.map(&:delete)
      assert_equal 0, q.size
    end

    it 'shows empty retries' do
      r = Sidekiq::RetrySet.new
      assert_equal 0, r.size
    end

    it 'can enumerate retries' do
      add_retry

      r = Sidekiq::RetrySet.new
      assert_equal 1, r.size
      array = r.to_a
      assert_equal 1, array.size

      retri = array.first
      assert_equal 'ApiWorker', retri.klass
      assert_equal 'default', retri.queue
      assert_equal 'bob', retri.jid
      assert_in_delta Time.now.to_f, retri.retry_at.to_f, 0.01
    end

    it 'can delete retries' do
      add_retry
      r = Sidekiq::RetrySet.new
      assert_equal 1, r.size
      r.map(&:delete)
      assert_equal 0, r.size
    end

    def add_retry
      at = Time.now.to_f
      payload = Sidekiq.dump_json('class' => 'ApiWorker', 'args' => [1, 'mike'], 'queue' => 'default', 'jid' => 'bob')
      Sidekiq.redis do |conn|
        conn.zadd('retry', at.to_s, payload)
      end
    end
  end
end
