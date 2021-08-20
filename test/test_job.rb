require_relative "helper"
require "sidekiq/job"

class TestJob < Minitest::Test
  class SomeJob
    include Sidekiq::Job
  end

  def test_sidekiq_job
    SomeJob.perform_async
    assert_equal "TestJob::SomeJob", Sidekiq::Queue.new.first.klass
  end
end
