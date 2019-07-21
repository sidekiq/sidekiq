# frozen_string_literal: true
require_relative 'helper'
require 'active_job'

describe 'ActiveJob' do
  it 'does not allow Sidekiq::Worker in AJ::Base classes' do
    ex = assert_raises ArgumentError do
      Class.new(ActiveJob::Base) do
        include Sidekiq::Worker
      end
    end
    assert_includes ex.message, "can only include Sidekiq::Worker::Options"
  end

  it 'allows Sidekiq::Options in AJ::Base classes' do
    Class.new(ActiveJob::Base) do
      include Sidekiq::Worker::Options
      sidekiq_options retry: true
      sidekiq_retry_in { |count, _exception| count * 10 }
      sidekiq_retries_exhausted do |msg, _exception|
        Sidekiq.logger.warn "Failed #{msg['class']} with #{msg['args']}: #{msg['error_message']}"
      end
    end
  end
end
