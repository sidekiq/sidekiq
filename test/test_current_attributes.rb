require_relative "./helper"
require "sidekiq/middleware/current_attributes"

module Myapp
  class Current < ActiveSupport::CurrentAttributes
    attribute :user_id
  end
end

class TestCurrentAttributes < Minitest::Test
  def test_save
    cm = Sidekiq::CurrentAttributes::Save.new(Myapp::Current)
    job = {}
    with_context(:user_id, 123) do
      cm.call(nil, job, nil, nil) do
        assert_equal 123, job["cattr"][:user_id]
      end
    end
  end

  def test_load
    cm = Sidekiq::CurrentAttributes::Load.new(Myapp::Current)

    job = { "cattr" => { "user_id" => 123 } }
    assert_nil Myapp::Current.user_id
    cm.call(nil, job, nil) do
      assert_equal 123, Myapp::Current.user_id
    end
    # the Rails reloader is responsible for reseting Current after every unit of work
  end

  def test_persist
    begin
      Sidekiq::CurrentAttributes.persist(Myapp::Current)
      job_hash = {}
      with_context(:user_id, 16) do
        Sidekiq.client_middleware.invoke(nil, job_hash, nil, nil) do
          assert_equal 16, job_hash["cattr"][:user_id]
        end
      end

      assert_nil Myapp::Current.user_id
      Sidekiq.server_middleware.invoke(nil, job_hash, nil) do
        assert_equal 16, job_hash["cattr"][:user_id]
        assert_equal 16, Myapp::Current.user_id
      end
      assert_nil Myapp::Current.user_id
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
