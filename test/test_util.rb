# frozen_string_literal: true
require_relative 'helper'

class TestUtil < Minitest::Test

  class Helpers
    include Sidekiq::Util
  end

  def test_event_firing
    Sidekiq.options[:lifecycle_events][:startup] = [proc { raise "boom" }]
    h = Helpers.new
    h.fire_event(:startup)

    Sidekiq.options[:lifecycle_events][:startup] = [proc { raise "boom" }]
    assert_raises RuntimeError do
      h.fire_event(:startup, reraise: true)
    end
  end
end
