require_relative 'helper'

class TestUtil < Sidekiq::Test

  class Helpers
    include Sidekiq::Util
  end

  def test_nothing_atm
    assert true
  end
end
