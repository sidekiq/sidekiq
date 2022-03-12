# frozen_string_literal: true

require_relative "helper"
require "sidekiq/util"

class TestUtil < Minitest::Test
  class Helpers
    include Sidekiq::Util
  end

  def test_event_firing
    before_handlers = Sidekiq.options[:lifecycle_events][:startup]
    begin
      Sidekiq.options[:lifecycle_events][:startup] = [proc { raise "boom" }]
      h = Helpers.new
      h.fire_event(:startup)

      Sidekiq.options[:lifecycle_events][:startup] = [proc { raise "boom" }]
      assert_raises RuntimeError do
        h.fire_event(:startup, reraise: true)
      end
    ensure
      Sidekiq.options[:lifecycle_events][:startup] = before_handlers
    end
  end
end
