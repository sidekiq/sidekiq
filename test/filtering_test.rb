require_relative "helper"
require "sidekiq/web"
require "rack/test"

class WebWorker
  include Sidekiq::Worker

  def perform(a, b)
    a + b
  end
end

describe "filtering" do
  before do
    @config = reset!
  end

  include Rack::Test::Methods

  def app
    Sidekiq::Web
  end

  it "can filter jobs" do
    jid1 = WebWorker.perform_in(5, "bob", "tammy")
    jid2 = WebWorker.perform_in(5, "mike", "jim")

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
