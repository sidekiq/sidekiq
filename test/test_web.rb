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
      Sidekiq.redis = { :url => 'redis://localhost/sidekiq_test' }
      Sidekiq.redis.flushdb
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
      assert_match last_response.body, /Sidekiq is down/
      refute_match last_response.body, /default/

      assert WebWorker.perform_async(1, 2)

      get '/'
      assert_equal 200, last_response.status
      assert_match last_response.body, /Sidekiq is down/
      assert_match last_response.body, /default/
      refute_match last_response.body, /foo/

      assert Sidekiq::Client.push(:foo, 'class' => WebWorker, 'args' => [1, 3])

      get '/'
      assert_equal 200, last_response.status
      assert_match last_response.body, /Sidekiq is down/
      assert_match last_response.body, /default/
      assert_match last_response.body, /foo/
    end

  end
end
