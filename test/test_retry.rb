require 'helper'
require 'sidekiq/retry'
require 'sidekiq/middleware/server/retry_jobs'

class TestRetry < MiniTest::Unit::TestCase
  describe 'middleware' do
    before do
      @redis = MiniTest::Mock.new
      # Ugh, this is terrible.
      Sidekiq.instance_variable_set(:@redis, @redis)

      def @redis.with; yield self; end
      @redis.expect :zadd, 1, ['retry', Float, String]
    end

    it 'handles a new failed message' do
      msg = { 'class' => 'Bob', 'args' => [1,2,'foo'] }
      handler = Sidekiq::Middleware::Server::RetryJobs.new
      assert_raises RuntimeError do
        handler.call('', msg, 'default') do
          raise "kerblammo!"
        end
      end
      assert_equal 'default', msg["queue"]
      assert_equal 'kerblammo!', msg["error_message"]
      assert_equal 'RuntimeError', msg["error_class"]
      assert_equal 0, msg["retry_count"]
      assert msg["failed_at"]
      @redis.verify
    end

    it 'handles a recurring failed message' do
      now = Time.now.utc
      msg = {"class"=>"Bob", "args"=>[1, 2, "foo"], "queue"=>"default", "error_message"=>"kerblammo!", "error_class"=>"RuntimeError", "failed_at"=>now, "retry_count"=>10}
      handler = Sidekiq::Middleware::Server::RetryJobs.new
      assert_raises RuntimeError do
        handler.call('', msg, 'default') do
          raise "kerblammo!"
        end
      end
      assert_equal 'default', msg["queue"]
      assert_equal 'kerblammo!', msg["error_message"]
      assert_equal 'RuntimeError', msg["error_class"]
      assert_equal 11, msg["retry_count"]
      assert msg["failed_at"]
      @redis.verify
    end
  end

  describe 'poller' do
    before do
      @redis = MiniTest::Mock.new
      Sidekiq.instance_variable_set(:@redis, @redis)

      fake_msg = MultiJson.encode({ 'class' => 'Bob', 'args' => [1,2], 'queue' => 'someq' })

      def @redis.with; yield self; end
      @redis.expect :zremrangebyscore, [fake_msg], ['retry', '-inf', String]
      @redis.expect :rpush, 1, ['someq', fake_msg]
    end

    it 'should poll like a bad mother...SHUT YO MOUTH' do
      inst = Sidekiq::Retry::Poller.new
      inst.poll
      @redis.verify
    end
  end

end
