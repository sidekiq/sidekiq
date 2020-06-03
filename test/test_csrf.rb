require_relative './helper'
require 'sidekiq/web/csrf_protection'

class TestCsrf < Minitest::Test
  def session
    @session ||= {}
  end

  def env(opts={})
    imp =  StringIO.new("")
    {
      "REQUEST_METHOD" => "GET",
      "rack.session" => session,
      "rack.logger" => ::Logger.new(@logio ||= StringIO.new("")),
      "rack.input" => imp,
      "rack.request.form_input" => imp,
      "rack.request.form_hash" => {},
    }.merge(opts)
  end

  def call(env, &block)
    Sidekiq::Web::CsrfProtection.new(block).call(env)
  end

  def test_get
    ok = [200, {}, ["OK"]]
    first = 1
    second = 1
    result = call(env) do |envy|
      refute_nil envy[:csrf_token]
      assert_equal 88, envy[:csrf_token].size
      first = envy[:csrf_token]
      ok
    end
    assert_equal ok, result

    result = call(env) do |envy|
      refute_nil envy[:csrf_token]
      assert_equal 88, envy[:csrf_token].size
      second = envy[:csrf_token]
      ok
    end
    assert_equal ok, result

    # verify masked token changes on every valid request
    refute_equal first, second
  end

  def test_bad_post
    result = call(env("REQUEST_METHOD" => "POST")) do
      raise "Shouldnt be called"
    end
    refute_nil result
    assert_equal 403, result[0]
    assert_equal ["Forbidden"], result[2]

    @logio.rewind
    assert_match(/attack prevented/, @logio.string)
  end

  def test_good_and_bad_posts
    goodtoken = nil
    # Make a GET to set up the session with a good token
    goodtoken = call(env) do |envy|
      envy[:csrf_token]
    end
    assert goodtoken

    # Make a POST with the known good token
    result = call(
      env({
        "REQUEST_METHOD" => "POST",
        "rack.request.form_hash" => { "authenticity_token"=>goodtoken }
      })) do
      [200, {}, ["OK"]]
    end
    refute_nil result
    assert_equal 200, result[0]
    assert_equal ["OK"], result[2]

    # Make a POST with a known bad token
    result = call(
      env({
        "REQUEST_METHOD" => "POST",
        "rack.request.form_hash" => { "authenticity_token"=>"N0QRBD34tU61d7fi+0ZaF/35JLW/9K+8kk8dc1TZoK/0pTl7GIHap5gy7BWGsoKlzbMLRp1yaDpCDFwTJtxWAg==", },
      })) do
      raise "shouldnt be called"
    end
    refute_nil result
    assert_equal 403, result[0]
    assert_equal ["Forbidden"], result[2]
  end
end
