# frozen_string_literal: true
require_relative 'helper'

class TestUtil < Sidekiq::Test
  include Sidekiq::Util

  def test_tid
    assert_equal "c3", tid(thread_id: 123, process_id: 456)
    assert_equal tid, tid
    refute_equal tid(thread_id: 1), tid(thread_id: 2)
    refute_equal tid(process_id: 1), tid(process_id: 2)
  end
end
