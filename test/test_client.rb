require 'helper'
require 'sidekiq/client'

class TestClient < MiniTest::Unit::TestCase
  def test_argument_handling
    assert_raises ArgumentError do
      Sidekiq::Client.push('foo', 1)
    end

    assert_raises ArgumentError do
      Sidekiq::Client.push('foo', :class => 'Foo', :noargs => [1, 2])
    end

    count = Sidekiq::Client.push('foo', :class => 'Foo', :args => [1, 2])
    assert count > 0
  end
end
