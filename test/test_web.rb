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

    it 'shows active queues' do
      get '/'
      assert_equal 200, last_response.status
      assert_match last_response.body, /Sidekiq is idle/
      refute_match last_response.body, /default/

      assert WebWorker.perform_async(1, 2)

      get '/'
      assert_equal 200, last_response.status
      assert_match last_response.body, /Sidekiq is idle/
      assert_match last_response.body, /default/
      refute_match last_response.body, /foo/

      assert Sidekiq::Client.push('queue' => :foo, 'class' => WebWorker, 'args' => [1, 3])

      get '/'
      assert_equal 200, last_response.status
      assert_match last_response.body, /Sidekiq is idle/
      assert_match last_response.body, /default/
      assert_match last_response.body, /foo/
    end

    it 'handles queues with no name' do
      get '/queues'
      assert_equal 404, last_response.status
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
  end
end
