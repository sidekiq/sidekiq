# frozen_string_literal: true
require_relative 'helper'

class TestUtil < Sidekiq::Test

  class Helpers
    include Sidekiq::Util
  end

  def test_tid
    x = Sidekiq::Util.tid
    y = nil
    t = Thread.new do
      Sidekiq::Util.tid
    end
    y = t.value
    assert x
    assert y
    refute_equal x, y
  end
end
