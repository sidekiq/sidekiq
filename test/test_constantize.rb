# frozen_string_literal: true

require_relative "helper"

class TestConstantize < Minitest::Test
  def test_constantize
    assert_equal Sidekiq, Sidekiq.constantize("Sidekiq")
    assert_equal Sidekiq, Sidekiq.constantize("::Sidekiq")
    assert_equal Sidekiq::Worker, Sidekiq.constantize("Sidekiq::Worker")
    assert_equal Sidekiq::Middleware::Chain, Sidekiq.constantize("::Sidekiq::Middleware::Chain")

    assert_raises NameError do
      Sidekiq.constantize("Sidekiq::Foo")
    end
  end
end
