require_relative "helper"

require "sidekiq/profiler"
require "sidekiq/api"
require "sidekiq/web"
require "rack/test"

describe "profiling" do
  before do
    @config = reset!

    # Ensure we don't touch external systems in our test suite
    Sidekiq::Web::PROFILE_OPTIONS.clear
    Sidekiq::Web::PROFILE_OPTIONS[:view_url] = "https://localhost/public/%s"
  end

  it "profiles" do
    ps = Sidekiq::ProfileSet.new
    assert_equal 0, ps.size

    skip("Not a usable Ruby") if RUBY_VERSION < "3.3"

    s = Sidekiq::Profiler.new(@config)
    assert_nil(s.call({}) {})
    result = s.call({"profile" => "mike", "class" => "SomeJob", "jid" => "1234"}) {
      sleep 0.001
      1
    }
    assert_kind_of Vernier::Result, result

    ps = Sidekiq::ProfileSet.new
    assert_equal 1, ps.size

    result = s.call({"profile" => "bob", "class" => "SomeJob", "jid" => "5678"}) {
      sleep 0.001
      1
    }
    assert_kind_of Vernier::Result, result
    ps = Sidekiq::ProfileSet.new
    assert_equal 2, ps.size

    profiles = ps.to_a
    assert_equal %w[bob-5678 mike-1234], profiles.map(&:key)
    assert_equal %w[5678 1234], profiles.map(&:jid)

    header = "\x1f\x8b".force_encoding("BINARY")
    profiles.each do |pr|
      assert pr.started_at
      assert_operator pr.size, :>, 2
      assert_operator pr.elapsed, :>, 0
      data = pr.data[0..1] # gzipped data
      assert_equal header, data # gzip magic number
    end

    get "/profiles"
    assert_match(/mike-1234/, last_response.body)
    assert_match(/bob-5678/, last_response.body)

    Sidekiq.redis { |c| c.hset("mike-1234", "sid", "sid1234") }
    Sidekiq.redis { |c| c.hset("bob-5678", "sid", "sid5678") }

    get "/profiles/mike-1234"
    assert_equal 302, last_response.status
    assert_equal "https://localhost/public/sid1234", last_response.headers["Location"]

    get "/profiles/mike-1234/data"
    assert_equal "application/json", last_response.headers["Content-Type"]
    assert_equal "gzip", last_response.headers["Content-Encoding"]
    assert_equal header, last_response.body[0..1]
  end

  include Rack::Test::Methods
  def session_secret
    "v3rys3cr31v3rys3cr31v3rys3cr31v3rys3cr31v3rys3cr31v3rys3cr31mike!"
  end

  def app
    @app ||= Sidekiq::Web.new
  end
end
