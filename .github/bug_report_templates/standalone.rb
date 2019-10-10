# frozen_string_literal: true

require "bundler/inline"

gemfile(true) do
  source "https://rubygems.org"

  git_source(:github) { |repo| "https://github.com/#{repo}.git" }

  # Use specific gem version
  gem "sidekiq", "6.0.1"
  # or master branch
  # gem "sidekiq", github: "mperham/sidekiq"
  gem "minitest"
end

require "sidekiq"
require "sidekiq/api"

ENV["REDIS_URL"] ||= "redis://localhost/15"

class BuggyWorker
  include Sidekiq::Worker
  sidekiq_options queue: "default"

  def perform
    puts "performed"
  end
end

require "minitest/autorun"

class BuggyWorkerTest < Minitest::Test
  def setup
    Sidekiq.redis { |c| c.flushdb }
  end

  def test_stuff
    q = Sidekiq::Queue.new("default")
    assert_equal 0, q.size
    BuggyWorker.perform_async
    assert_equal 1, q.size
  end
end
