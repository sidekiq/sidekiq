# frozen_string_literal: true

require_relative "helper"
require "sidekiq/web"

describe Sidekiq::Web::Route do
  describe "a plain string path" do
    let(:route) { Sidekiq::Web::Route.new(:get, "/dashboard", nil) }

    it "matches the exact path with an empty params hash" do
      assert_equal Sidekiq::Web::Route::EMPTY, route.match(:get, "/dashboard")
    end

    it "does not match a different path" do
      assert_nil route.match(:get, "/other")
    end

    it "does not match a path with extra segments" do
      assert_nil route.match(:get, "/dashboard/extra")
    end

    it "compiles to a String, not a Regexp" do
      assert_kind_of String, route.matcher
    end
  end

  describe "a path with a single named segment" do
    let(:route) { Sidekiq::Web::Route.new(:get, "/queues/:name", nil) }

    it "compiles to a Regexp with a named capture" do
      assert_kind_of Regexp, route.matcher
    end

    it "captures the segment under a symbol key" do
      assert_equal({name: "critical"}, route.match(:get, "/queues/critical"))
    end

    it "returns nil for a path missing the segment" do
      assert_nil route.match(:get, "/queues")
    end

    it "returns nil for a path with an extra segment" do
      assert_nil route.match(:get, "/queues/critical/extra")
    end
  end

  describe "a path with multiple named segments" do
    let(:route) { Sidekiq::Web::Route.new(:get, "/queues/:name/jobs/:jid", nil) }

    it "captures every segment under a symbol key" do
      assert_equal({name: "q1", jid: "abc123"}, route.match(:get, "/queues/q1/jobs/abc123"))
    end

    it "returns nil when only part of the path matches" do
      assert_nil route.match(:get, "/queues/q1/jobs")
    end
  end
end
