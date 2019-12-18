# frozen_string_literal: true
require_relative 'helper'
require 'sidekiq/rails'
require 'sidekiq/api'

describe 'ActiveJob' do
  before do
    Sidekiq.redis {|c| c.flushdb }
    # need to force this since we aren't booting a Rails app
    ActiveJob::Base.queue_adapter = :sidekiq
    ActiveJob::Base.logger = nil
    ActiveJob::Base.send(:include, ::Sidekiq::Worker::Options) unless ActiveJob::Base.respond_to?(:sidekiq_options)
  end

  it 'does not allow Sidekiq::Worker in AJ::Base classes' do
    ex = assert_raises ArgumentError do
      Class.new(ActiveJob::Base) do
        include Sidekiq::Worker
      end
    end
    assert_includes ex.message, "Sidekiq::Worker cannot be included"
  end

  it 'loads Sidekiq::Worker::Options in AJ::Base classes' do
    aj = Class.new(ActiveJob::Base) do
      queue_as :bar
      sidekiq_options retry: 4, queue: 'foo', backtrace: 5
      sidekiq_retry_in { |count, _exception| count * 10 }
      sidekiq_retries_exhausted do |msg, _exception|
        Sidekiq.logger.warn "Failed #{msg['class']} with #{msg['args']}: #{msg['error_message']}"
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
  end
end
