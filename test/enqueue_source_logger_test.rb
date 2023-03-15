# frozen_string_literal: true

require_relative "./helper"
require_relative "./dummy/app/services/dummy_service"

describe "EnqueueSourceLogger" do
  before do
    require "sidekiq/middleware/enqueue_source_logger"
  end

  it "logs enqueue source" do
    config = Sidekiq.default_configuration
    previous_cleaner = config[:backtrace_cleaner]
    config[:backtrace_cleaner] = ->(backtrace) { backtrace.select { |line| line.include?("dummy/app/") } }

    output = capture_logging(config) do
      DummyService.do_something
    end

    assert_match(/DummyJob enqueued\n\s+↳ .+:\d+:in `do_something/, output)
  ensure
    config[:backtrace_cleaner] = previous_cleaner
  end
end
