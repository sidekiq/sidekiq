require_relative "./helper"
require "sidekiq/middleware/current_attributes"

module Myapp
  class Current < ActiveSupport::CurrentAttributes
    attribute :user_id
  end
end

class TestCurrentAttributes < Minitest::Test
  def test_save
    cm = Sidekiq::CurrentAttributes::Save.new(with: Myapp::Current)
    job = {}
    with_context(:user_id, 123) do
      cm.call(nil, job, nil, nil) do
        assert_equal 123, job["ctx"][:user_id]
      end
    end
  end

  def test_load
    cm = Sidekiq::CurrentAttributes::Load.new(with: Myapp::Current)

    job = { "ctx" => { "user_id" => 123 } }
    assert_nil Myapp::Current.user_id
    cm.call(nil, job, nil) do
      assert_equal 123, Myapp::Current.user_id
    end
    # the Rails reloader is responsible for reseting Current after every unit of work
  end

  def test_persist
    begin
      Sidekiq::CurrentAttributes.persist(Myapp::Current)
    ensure
      Sidekiq.client_middleware.clear
      Sidekiq.server_middleware.clear
    end
  end

  private

  def with_context(attr, value)
    begin
      Myapp::Current.send("#{attr}=", value)
      yield
    ensure
      Myapp::Current.reset_all
    end
  end
end
