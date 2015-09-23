require_relative 'helper'

class TestUtil < Sidekiq::Test

  class Helpers
    include Sidekiq::Util
  end

  def test_hertz_donut
    obj = Helpers.new
    output = capture_logging(Logger::DEBUG) do
      assert_equal false, obj.want_a_hertz_donut?
    end
    assert_includes output, "hz: 10"
  end
end
