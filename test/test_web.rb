require 'helper'
require 'sidekiq'
require 'sidekiq/web'
require 'rack/test'

class TestWeb < MiniTest::Unit::TestCase
  describe 'sidekiq web' do
    include Rack::Test::Methods

    def app
      Sidekiq::Web
    end

    def job_params(job, score)
      "#{score}-#{job['jid']}"
    end

    before do
      Sidekiq.redis = REDIS
      Sidekiq.redis {|c| c.flushdb }
    end

    class WebWorker
      include Sidekiq::Worker

      def perform(a, b)
        a + b
      end
    end

    it 'can display workers' do
      Sidekiq.redis do |conn|
        identity = 'foo:1234-123abc:default'
        conn.sadd('workers', identity)
        conn.setex("worker:#{identity}:started", 10, Time.now.to_s)
        hash = {:queue => 'critical', :payload => { 'class' => WebWorker.name, 'args' => [1,'abc'] }, :run_at => Time.now.to_i }
        conn.setex("worker:#{identity}", 10, Sidekiq.dump_json(hash))
      end

      get '/workers'
      assert_equal 200, last_response.status
      assert_match /status-active/, last_response.body
      assert_match /critical/, last_response.body
      assert_match /WebWorker/, last_response.body
    end

    it 'can display queues' do
      assert Sidekiq::Client.push('queue' => :foo, 'class' => WebWorker, 'args' => [1, 3])

      get '/queues'
      assert_equal 200, last_response.status
      assert_match /foo/, last_response.body
      refute_match /HardWorker/, last_response.body
    end

    it 'handles queue view' do
      get '/queues/default'
      assert_equal 200, last_response.status
    end

    it 'can delete a queue' do
      Sidekiq.redis do |conn|
        conn.rpush('queue:foo', '{}')
        conn.sadd('queues', 'foo')
      end

      get '/queues/foo'
      assert_equal 200, last_response.status

      post '/queues/foo'
      assert_equal 302, last_response.status

      Sidekiq.redis do |conn|
        refute conn.smembers('queues').include?('foo')
        refute conn.exists('queues:foo')
      end
    end

    it 'can delete a job' do
      Sidekiq.redis do |conn|
        conn.rpush('queue:foo', "{}")
        conn.rpush('queue:foo', "{\"foo\":\"bar\"}")
        conn.rpush('queue:foo', "{\"foo2\":\"bar2\"}")
      end

      get '/queues/foo'
      assert_equal 200, last_response.status

      post '/queues/foo/delete', key_val: "{\"foo\":\"bar\"}"
      assert_equal 302, last_response.status

      Sidekiq.redis do |conn|
        refute conn.lrange('queue:foo', 0, -1).include?("{\"foo\":\"bar\"}")
      end
    end

    it 'can display retries' do
      get '/retries'
      assert_equal 200, last_response.status
      assert_match /found/, last_response.body
      refute_match /HardWorker/, last_response.body

      add_retry

      get '/retries'
      assert_equal 200, last_response.status
      refute_match /found/, last_response.body
      assert_match /HardWorker/, last_response.body
    end

    it 'can display a single retry' do
      params = add_retry
      get '/retries/2c4c17969825a384a92f023b'
      assert_equal 302, last_response.status
      get "/retries/#{job_params(*params)}"
      assert_equal 200, last_response.status
      assert_match /HardWorker/, last_response.body
    end

    it 'handles missing retry' do
      get "/retries/2c4c17969825a384a92f023b"
      assert_equal 302, last_response.status
    end

    it 'can delete a single retry' do
      params = add_retry
      post "/retries/#{job_params(*params)}", 'delete' => 'Delete'
      assert_equal 302, last_response.status
      assert_equal 'http://example.org/retries', last_response.header['Location']

      get "/retries"
      assert_equal 200, last_response.status
      refute_match /#{params.first['args'][2]}/, last_response.body
    end

    it 'can delete all retries' do
      3.times { add_retry }

      post "/retries/all/delete", 'delete' => 'Delete'
      assert_equal 0, Sidekiq::RetrySet.new.size
      assert_equal 302, last_response.status
      assert_equal 'http://example.org/retries', last_response.header['Location']
    end

    it 'can retry a single retry now' do
      params = add_retry
      post "/retries/#{job_params(*params)}", 'retry' => 'Retry'
      assert_equal 302, last_response.status
      assert_equal 'http://example.org/retries', last_response.header['Location']

      get '/queues/default'
      assert_equal 200, last_response.status
      assert_match /#{params.first['args'][2]}/, last_response.body
    end

    it 'can display scheduled' do
      get '/scheduled'
      assert_equal 200, last_response.status
      assert_match /found/, last_response.body
      refute_match /HardWorker/, last_response.body

      add_scheduled

      get '/scheduled'
      assert_equal 200, last_response.status
      refute_match /found/, last_response.body
      assert_match /HardWorker/, last_response.body
    end

    it 'can delete scheduled' do
      params = add_scheduled
      Sidekiq.redis do |conn|
        assert_equal 1, conn.zcard('schedule')
        post '/scheduled', 'key' => [job_params(*params)], 'delete' => 'Delete'
        assert_equal 302, last_response.status
        assert_equal 'http://example.org/scheduled', last_response.header['Location']
        assert_equal 0, conn.zcard('schedule')
      end
    end

    it 'can retry all retries' do
      msg, score = add_retry
      add_retry

      post "/retries/all/retry", 'retry' => 'Retry'
      assert_equal 302, last_response.status
      assert_equal 'http://example.org/retries', last_response.header['Location']
      assert_equal 2, Sidekiq::Queue.new("default").size

      get '/queues/default'
      assert_equal 200, last_response.status
      assert_match /#{msg['args'][2]}/, last_response.body
    end

    it 'can show user defined tab' do
      begin
        Sidekiq::Web.tabs['Custom Tab'] = '/custom'

        get '/'
        assert_match 'Custom Tab', last_response.body

      ensure
        Sidekiq::Web.tabs.delete 'Custom Tab'
      end
    end

    it 'can display home' do
      get '/'
      assert_equal 200, last_response.status
    end

    describe 'stats' do
      before do
        Sidekiq.redis do |conn|
          conn.set("stat:processed", 5)
          conn.set("stat:failed", 2)
        end
        2.times { add_retry }
        3.times { add_scheduled }
        4.times { add_worker }

        get '/dashboard/stats'
        @response = Sidekiq.load_json(last_response.body)
      end

      it 'can refresh dashboard stats' do
        assert_equal 200, last_response.status
      end

      describe "for sidekiq" do
        it 'are namespaced' do
          assert_includes @response.keys, "sidekiq"
        end

        it 'reports processed' do
          assert_equal 5, @response["sidekiq"]["processed"]
        end

        it 'reports failed' do
          assert_equal 2, @response["sidekiq"]["failed"]
        end

        it 'reports busy' do
          assert_equal 4, @response["sidekiq"]["busy"]
        end

        it 'reports retries' do
          assert_equal 2, @response["sidekiq"]["retries"]
        end

        it 'reports scheduled' do
          assert_equal 3, @response["sidekiq"]["scheduled"]
        end
      end

      describe "for redis" do
        it 'are namespaced' do
          assert_includes @response.keys, "redis"
        end
      end
    end

    def add_scheduled
      score = Time.now.to_f
      msg = { 'class' => 'HardWorker',
              'args' => ['bob', 1, Time.now.to_f],
              'at' => score,
              'jid' => 'f39af2a05e8f4b24dbc0f1e4' }
      Sidekiq.redis do |conn|
        conn.zadd('schedule', score, Sidekiq.dump_json(msg))
      end
      [msg, score]
    end

    def add_retry
      msg = { 'class' => 'HardWorker',
              'args' => ['bob', 1, Time.now.to_f],
              'queue' => 'default',
              'error_message' => 'Some fake message',
              'error_class' => 'RuntimeError',
              'retry_count' => 0,
              'failed_at' => Time.now.utc,
              'jid' => 'f39af2a05e8f4b24dbc0f1e4'}
      score = Time.now.to_f
      Sidekiq.redis do |conn|
        conn.zadd('retry', score, Sidekiq.dump_json(msg))
      end
      [msg, score]
    end

    def add_worker
      process_id = rand(1000)
      msg = "{\"queue\":\"default\",\"payload\":{\"retry\":true,\"queue\":\"default\",\"timeout\":20,\"backtrace\":5,\"class\":\"HardWorker\",\"args\":[\"bob\",10,5],\"jid\":\"2b5ad2b016f5e063a1c62872\"},\"run_at\":1361208995}"
      Sidekiq.redis do |conn|
        conn.sadd("workers", "mercury.home:#{process_id}-70215157189060:started")
        conn.set("worker:mercury.home:#{process_id}-70215157189060:started", msg)
      end
    end
  end
end
