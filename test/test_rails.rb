# frozen_string_literal: true
require_relative 'helper'
require 'active_job'

describe 'ActiveJob' do
  it 'does not allow Sidekiq::Worker in AJ::Base classes' do
    ex = assert_raises ArgumentError do
      c = Class.new(ActiveJob::Base)
      c.send(:include, Sidekiq::Worker)
    end
    assert_includes ex.message, "cannot include"
  end
end
