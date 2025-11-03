# frozen_string_literal: true

require_relative "helper"
require "active_job"
require "sidekiq/api"

describe "ActiveJob" do
  before do
    ActiveJob::Base.queue_adapter = :sidekiq
    @config = reset!
    @config[:backtrace_cleaner] = ->(backtrace) { Rails.backtrace_cleaner.clean(backtrace) }
  end

  it "does not allow Sidekiq::Job in AJ::Base classes" do
    ex = assert_raises ArgumentError do
      Class.new(ActiveJob::Base) do
        include Sidekiq::Job
      end
    end
    assert_includes ex.message, "Sidekiq::Job cannot be included"
  end

  it "loads Sidekiq::Job::Options in AJ::Base classes" do
    aj = Class.new(ActiveJob::Base) do
      queue_as :bar
      sidekiq_options retry: 4, queue: "foo", backtrace: 5
      sidekiq_retry_in { |count, _exception| count * 10 }
      sidekiq_retries_exhausted do |msg, _exception|
        @config.logger.warn "Failed #{msg["class"]} with #{msg["args"]}: #{msg["error_message"]}"
      end
    end

    assert_equal 4, aj.get_sidekiq_options["retry"]

    # When using ActiveJobs, you cannot set the queue with sidekiq_options, you must use
    # queue_as or set(queue: ...).  This is to avoid duplicate ways of doing the same thing.
    instance = aj.perform_later(1, 2, 3)
    q = Sidekiq::Queue.new("foo")
    assert_equal 0, q.size
    q = Sidekiq::Queue.new("bar")
    assert_equal 1, q.size
    assert_equal 24, instance.provider_job_id.size

    job = q.first
    assert_equal 4, job["retry"]
    assert_equal 5, job["backtrace"]
    # AJ's queue_as should take precedence over Sidekiq's queue option
    assert_equal "bar", job["queue"]
  end

  it "doesn't load ActiveJob::Base before Rails initialization is complete" do
    # Rails sets ActiveJob::Base to an ActiveSupport::Logger by default,
    # but we override config.active_job.logger in dummy/config/initializers/active_job.rb to a regular ::Logger.
    # Check that that config has taken effect - if not, it implies that ActiveJob::Base got loaded
    # before our initializer is complete.
    app_dir = File.expand_path("./dummy", __dir__)
    logger_class = IO.popen(["bin/rails", "runner", "puts ActiveJob::Base.logger.class"], chdir: app_dir).read.chomp
    assert_equal "Logger", logger_class
  end
end
