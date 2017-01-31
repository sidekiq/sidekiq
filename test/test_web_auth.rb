# encoding: utf-8
# frozen_string_literal: true
require_relative 'helper'
require 'sidekiq/web'
require 'rack/test'

class TestWebAuth < Sidekiq::Test
  describe 'sidekiq web with basic auth' do
    include Rack::Test::Methods

    def app
      app = Sidekiq::Web.new
      app.use(Rack::Auth::Basic) { |user, pass| user == "a" && pass == "b" }

      app
    end

    it 'requires basic authentication' do
      get '/'

      assert_equal 401, last_response.status
      refute_nil last_response.header["WWW-Authenticate"]
    end

    it 'authenticates successfuly' do
      basic_authorize 'a', 'b'

      get '/'

      assert_equal 200, last_response.status
    end
  end

  describe 'sidekiq web with custom session' do
    include Rack::Test::Methods

    def app
      app = Sidekiq::Web.new

      app.use Rack::Session::Cookie, secret: 'v3rys3cr31', host: 'nicehost.org'

      app
    end

    it 'requires basic authentication' do
      get '/'

      session_options = last_request.env['rack.session'].options

      assert_equal 'v3rys3cr31', session_options[:secret]
      assert_equal 'nicehost.org', session_options[:host]
    end
  end
end
