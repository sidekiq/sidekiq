# frozen_string_literal: true

require_relative "helper"
require "sidekiq/web"
require "rack/test"
require "rack/session"

class MyExt
  VIEWS = File.expand_path("fixtures", File.dirname(__FILE__))

  def self.registered(app)
    app.get "/foobar" do
      render(:erb, "My Index Route")
    end
    app.get "/foobar/:name" do
      @name = route_params(:name)
      @time = url_params("time")
      erb :foobar, views: VIEWS
    end
  end
end

describe Sidekiq::Web::Config do
  include Rack::Test::Methods

  def app
    @app ||= Rack::Lint.new(Sidekiq::Web.new)
  end

  before do
    @config = reset!

    Sidekiq::Web.configure do |c|
      c.middlewares.clear
      c.use Rack::Session::Cookie, secrets: "35c5108120cb479eecb4e947e423cad6da6f38327cf0ebb323e30816d74fa01f"
    end
  end

  it "allows web ui extensions" do
    Sidekiq::Web.configure do |config|
      config.register_extension(MyExt,
        name: "myext",
        tab: "MyExt",
        index: "foobar",
        root_dir: ".")
    end

    get "/foobar"
    assert_match(/My Index Route/, last_response.body)
    time = Time.now.to_i
    get "/foobar/mike?time=#{time}"
    assert_match(/Hello, mike, it is #{time}/, last_response.body)
  end
end
