require_relative "helper"
require "sidekiq/web"
require "rack/test"

class FilterJob
  include Sidekiq::Job

  def perform(a, b)
    a + b
  end
end

class FilteringTest < Minitest::Test
  include Rack::Test::Methods

  def setup
    @config = reset!
    app.middlewares.clear
  end

  def app
    Sidekiq::Web
  end

  def test_job_filtering
    jid1 = FilterJob.perform_in(5, "bob", "tammy")
    jid2 = FilterJob.perform_in(5, "mike", "jim")

    get "/scheduled"
    assert_equal 200, last_response.status
    assert_match(/#{jid1}/, last_response.body)
    assert_match(/#{jid2}/, last_response.body)

    post "/filter/scheduled", substr: "tammy"
    assert_equal 200, last_response.status
    assert_match(/#{jid1}/, last_response.body)
    refute_match(/#{jid2}/, last_response.body)

    post "/filter/scheduled", substr: ""
    assert_equal 302, last_response.status
    get "/filter/scheduled"
    assert_equal 302, last_response.status
    get "/filter/retries"
    assert_equal 302, last_response.status
    get "/filter/dead"
    assert_equal 302, last_response.status
  end
end
