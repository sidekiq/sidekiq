# frozen_string_literal: true

require "bundler/inline"

gemfile(true) do
  source "https://rubygems.org"

  git_source(:github) { |repo| "https://github.com/#{repo}.git" }

  # Use specific gem version
  gem "sidekiq", "6.0.1"
  # or master branch
  # gem "sidekiq", github: "mperham/sidekiq"

  gem "rails", "6.0.0"
  # gem "rails", github: "rails/rails"
  gem "minitest"
end

require "sidekiq"
require "active_job"
require "active_job/railtie"
require "logger"

ENV["REDIS_URL"] ||= "redis://localhost/15"

class TestApp < Rails::Application
  config.active_job.queue_adapter = :sidekiq

  config.logger = Logger.new(STDOUT)
  Sidekiq.logger = config.logger
end

class BuggyJob < ActiveJob::Base
  def perform
    puts "performed"
  end
end

require "minitest/autorun"

class BuggyJobTest < ActiveJob::TestCase
  def test_stuff
    assert_enqueued_with(job: BuggyJob) do
      BuggyJob.perform_later
    end
  end
end
