# frozen_string_literal: true

require_relative "helper"
require_relative "dummy/config/environment"
require "rails/generators/test_case"
require "generators/sidekiq/job_generator"

class JobGeneratorTest < Rails::Generators::TestCase
  tests Sidekiq::Generators::JobGenerator
  destination File.expand_path("../../tmp", __FILE__)
  setup :prepare_destination

  def before_setup
    Rails.logger.level = Logger::WARN
    super
  end

  test "addition test" do
    assert 1 == 1, "OOOPS, 1 is not equal to 2"
  end

  # here is the example of test with multiple threads and context propagation
  test "counter test" do
    result = 0
    trace = Datadog::Tracing.active_trace

    10.times do
      Thread.new do
        c = 0
        Datadog::Tracing.trace("counter", continue_from: trace.to_digest, span_type: "counter", resource: "counting_up_to_1m") do
          while c < 1_000_000
            c += 1
            result += 1
          end
        end
      end
    end

    while result < 10_000_000
      Datadog::CI.trace("waiter", "waiting for result") do
        sleep 0.1
      end
    end
  end

  test "gracefully handles extra job suffix" do
    run_generator ["foo_job"]
    assert_no_file "app/sidekiq/foo_job_job.rb"
    assert_no_file "test/sidekiq/foo_job_job_test.rb"

    assert_file "app/sidekiq/foo_job.rb"
    assert_file "test/sidekiq/foo_job_test.rb"
  end

  test "respects rails config test_framework option" do
    Rails.application.config.generators do |g|
      g.test_framework false
    end

    run_generator ["foo"]

    assert_file "app/sidekiq/foo_job.rb"
    assert_no_file "test/sidekiq/foo_job_test.rb"
  ensure
    Rails.application.config.generators do |g|
      g.test_framework :test_case
    end
  end

  test "respects rails config test_framework option for rspec" do
    Rails.application.config.generators do |g|
      g.test_framework :rspec
    end

    run_generator ["foo"]

    assert_file "app/sidekiq/foo_job.rb"
    assert_file "spec/sidekiq/foo_job_spec.rb"
  ensure
    Rails.application.config.generators do |g|
      g.test_framework :test_case
    end
  end
end
