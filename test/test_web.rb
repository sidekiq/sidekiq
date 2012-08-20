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

    it 'can display home' do
      get '/'
      assert_equal 200, last_response.status
      assert_match /Sidekiq is idle/, last_response.body
      refute_match /default/, last_response.body
    end

    it 'can display poll' do
      get '/poll'
      assert_equal 200, last_response.status
      assert_match /hero-unit/, last_response.body
      assert_match /workers/, last_response.body
      refute_match /navbar/, last_response.body
    end

    it 'can display queues' do
      assert Sidekiq::Client.push('queue' => :foo, 'class' => WebWorker, 'args' => [1, 3])

      get '/queues'
      assert_equal 200, last_response.status
      assert_match /foo/, last_response.body
      refute_match /HardWorker/, last_response.body
    end

    it 'handles missing retry' do
      get '/retries/12391982.123'
      assert_equal 302, last_response.status
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
      end
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
      msg,score = add_scheduled
      Sidekiq.redis do |conn|
        assert_equal 1, conn.zcard('schedule')
        post '/scheduled', 'score' => [score], 'delete' => 'Delete'
        assert_equal 302, last_response.status
        assert_equal 'http://example.org/scheduled', last_response.header['Location']
        assert_equal 0, conn.zcard('schedule')
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
      get '/retries/12938712.123333'
      assert_equal 302, last_response.status
      _, score = add_retry

      get "/retries/#{score}"
      assert_equal 200, last_response.status
      assert_match /HardWorker/, last_response.body
    end

    it 'can delete a single retry' do
      _, score = add_retry

      post "/retries/#{score}", 'delete' => 'Delete'
      assert_equal 302, last_response.status
      assert_equal 'http://example.org/retries', last_response.header['Location']

      get "/retries"
      assert_equal 200, last_response.status
      refute_match /#{score}/, last_response.body
    end

    it 'can retry a single retry now' do
      msg, score = add_retry

      post "/retries/#{score}", 'retry' => 'Retry'
      assert_equal 302, last_response.status
      assert_equal 'http://example.org/retries', last_response.header['Location']

      get '/queues/default'
      assert_equal 200, last_response.status
      assert_match /#{msg['args'][2]}/, last_response.body
    end

    it 'can show user defined tab' do
      Sidekiq::Web.tabs << 'Custom Tab'

      get '/'
      assert_match 'Custom Tab', last_response.body

      Sidekiq::Web.tabs.delete 'Custom Tab'
    end

    def add_scheduled
      msg = { 'class' => 'HardWorker',
              'args' => ['bob', 1, Time.now.to_f],
              'at' => Time.now.to_f }
      score = Time.now.to_f
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
              'failed_at' => Time.now.utc, }
      score = Time.now.to_f
      Sidekiq.redis do |conn|
        conn.zadd('retry', score, Sidekiq.dump_json(msg))
      end
      [msg, score]
    end
  end
end
