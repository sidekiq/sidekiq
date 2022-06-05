# frozen_string_literal: true

require_relative "helper"
require "sidekiq/cli"
require "sidekiq/job"

describe Sidekiq::Job do
  class SomeJob
    include Sidekiq::Job
  end

  it "adds job to queue" do
    SomeJob.perform_async
    assert_equal "SomeJob", Sidekiq::Queue.new.first.klass
  end
end
