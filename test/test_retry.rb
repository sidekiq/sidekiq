require 'helper'
require 'sidekiq/scheduled'
require 'sidekiq/middleware/server/retry_jobs'

class TestRetry < MiniTest::Unit::TestCase
  describe 'middleware' do
    before do
      @redis = MiniTest::Mock.new
      # Ugh, this is terrible.
      Sidekiq.instance_variable_set(:@redis, @redis)

      def @redis.with; yield self; end
    end

    it 'allows disabling retry' do
      msg = { 'class' => 'Bob', 'args' => [1,2,'foo'], 'retry' => false }
      msg2 = msg.dup
      handler = Sidekiq::Middleware::Server::RetryJobs.new
      assert_raises RuntimeError do
        handler.call('', msg2, 'default') do
          raise "kerblammo!"
        end
      end
      assert_equal msg, msg2
    end

    it 'allows a numeric retry' do
      @redis.expect :zadd, 1, ['retry', String, String]
      msg = { 'class' => 'Bob', 'args' => [1,2,'foo'], 'retry' => 2 }
      msg2 = msg.dup
      handler = Sidekiq::Middleware::Server::RetryJobs.new
      assert_raises RuntimeError do
        handler.call('', msg2, 'default') do
          raise "kerblammo!"
        end
      end
      msg2.delete('failed_at')
      assert_equal({"class"=>"Bob", "args"=>[1, 2, "foo"], "retry"=>2, "queue"=>"default", "error_message"=>"kerblammo!", "error_class"=>"RuntimeError", "retry_count"=>0}, msg2)
      @redis.verify
    end

    it 'saves backtraces' do
      @redis.expect :zadd, 1, ['retry', String, String]
      msg = { 'class' => 'Bob', 'args' => [1,2,'foo'], 'retry' => true, 'backtrace' => true }
      handler = Sidekiq::Middleware::Server::RetryJobs.new
      c = nil
      assert_raises RuntimeError do
        handler.call('', msg, 'default') do
          c = caller(0); raise "kerblammo!"
        end
      end
      assert msg["error_backtrace"]
      assert_equal c[0], msg["error_backtrace"][0]
      @redis.verify
    end

    it 'saves partial backtraces' do
      @redis.expect :zadd, 1, ['retry', String, String]
      msg = { 'class' => 'Bob', 'args' => [1,2,'foo'], 'retry' => true, 'backtrace' => 3 }
      handler = Sidekiq::Middleware::Server::RetryJobs.new
      c = nil
      assert_raises RuntimeError do
        handler.call('', msg, 'default') do
          c = caller(0)[0..3]; raise "kerblammo!"
        end
      end
      assert msg["error_backtrace"]
      assert_equal c, msg["error_backtrace"]
    end

    it 'handles a new failed message' do
      @redis.expect :zadd, 1, ['retry', String, String]
      msg = { 'class' => 'Bob', 'args' => [1,2,'foo'], 'retry' => true }
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
      refute msg["error_backtrace"]
      assert msg["failed_at"]
      @redis.verify
    end

    it 'allows a retry queue' do
      @redis.expect :zadd, 1, ['retry', String, String]
      msg = { 'class' => 'Bob', 'args' => [1,2,'foo'], 'retry' => true, 'retry_queue' => 'retry' }
      handler = Sidekiq::Middleware::Server::RetryJobs.new
      assert_raises RuntimeError do
        handler.call('', msg, 'default') do
          raise "kerblammo!"
        end
      end
      assert_equal 'retry', msg["queue"]
      assert_equal 'kerblammo!', msg["error_message"]
      assert_equal 'RuntimeError', msg["error_class"]
      assert_equal 0, msg["retry_count"]
      refute msg["error_backtrace"]
      assert msg["failed_at"]
      @redis.verify
    end

    it 'handles a recurring failed message' do
      @redis.expect :zadd, 1, ['retry', String, String]
      now = Time.now.utc
      msg = {"class"=>"Bob", "args"=>[1, 2, "foo"], 'retry' => true, "queue"=>"default", "error_message"=>"kerblammo!", "error_class"=>"RuntimeError", "failed_at"=>now, "retry_count"=>10}
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

    it 'handles a recurring failed message before reaching user-specifed max' do
      @redis.expect :zadd, 1, ['retry', String, String]
      now = Time.now.utc
      msg = {"class"=>"Bob", "args"=>[1, 2, "foo"], 'retry' => 10, "queue"=>"default", "error_message"=>"kerblammo!", "error_class"=>"RuntimeError", "failed_at"=>now, "retry_count"=>8}
      handler = Sidekiq::Middleware::Server::RetryJobs.new
      assert_raises RuntimeError do
        handler.call('', msg, 'default') do
          raise "kerblammo!"
        end
      end
      assert_equal 'default', msg["queue"]
      assert_equal 'kerblammo!', msg["error_message"]
      assert_equal 'RuntimeError', msg["error_class"]
      assert_equal 9, msg["retry_count"]
      assert msg["failed_at"]
      @redis.verify
    end

    it 'throws away old messages after too many retries (using the default)' do
      now = Time.now.utc
      msg = {"class"=>"Bob", "args"=>[1, 2, "foo"], "queue"=>"default", "error_message"=>"kerblammo!", "error_class"=>"RuntimeError", "failed_at"=>now, "retry"=>true, "retry_count"=>25}
      @redis.expect :zadd, 1, [ 'retry', String, String ]
      handler = Sidekiq::Middleware::Server::RetryJobs.new
      assert_raises RuntimeError do
        handler.call('', msg, 'default') do
          raise "kerblammo!"
        end
      end
      # MiniTest can't assert that a method call did NOT happen!?
      assert_raises(MockExpectationError) { @redis.verify }
    end

    it 'throws away old messages after too many retries (using user-specified max)' do
      now = Time.now.utc
      msg = {"class"=>"Bob", "args"=>[1, 2, "foo"], "queue"=>"default", "error_message"=>"kerblammo!", "error_class"=>"RuntimeError", "failed_at"=>now, "retry"=>3, "retry_count"=>3}
      @redis.expect :zadd, 1, [ 'retry', String, String ]
      handler = Sidekiq::Middleware::Server::RetryJobs.new
      assert_raises RuntimeError do
        handler.call('', msg, 'default') do
          raise "kerblammo!"
        end
      end
      # MiniTest can't assert that a method call did NOT happen!?
      assert_raises(MockExpectationError) { @redis.verify }
    end

    describe "retry exhaustion" do
      let(:worker){ MiniTest::Mock.new }
      let(:handler){ Sidekiq::Middleware::Server::RetryJobs.new }
      let(:msg){ {"class"=>"Bob", "args"=>[1, 2, "foo"], "queue"=>"default", "error_message"=>"kerblammo!", "error_class"=>"RuntimeError", "failed_at"=>Time.now.utc, "retry"=>3, "retry_count"=>3} }

      it 'calls worker retries_exhausted after too many retries' do
        worker.expect(:retries_exhausted, true, [1,2,"foo"]) 
        task_misbehaving_worker
        worker.verify
      end

      it 'handles and logs retries_exhausted failures gracefully (drops them)' do
        def worker.retries_exhausted(*args)
          raise 'bam!'
        end

        e = task_misbehaving_worker
        assert_equal e.message, "kerblammo!"
        worker.verify
      end

      def task_misbehaving_worker
        assert_raises RuntimeError do
          handler.call(worker, msg, 'default') do
            raise 'kerblammo!'
          end
        end
      end
    end
  end

end
