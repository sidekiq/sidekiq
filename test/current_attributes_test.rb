# frozen_string_literal: true

require_relative "helper"
require "sidekiq/middleware/current_attributes"

module Myapp
  class Current < ActiveSupport::CurrentAttributes
    attribute :user_id
  end

  class OtherCurrent < ActiveSupport::CurrentAttributes
    attribute :other_id
  end
end

class CurrentAttributesJob
  include Sidekiq::Job

  def perform
  end
end

Serializer = ActiveJob::Arguments

class TestCurrentAttributes < Minitest::Test
  def setup
    @config = reset!
  end

  def run
    # Rails reloader auto-clears context
    Rails.application.reloader.wrap { super }
  end

  def test_saves
    cm = Sidekiq::CurrentAttributes::Save.new({
      "cattr" => "Myapp::Current",
      "cattr_1" => "Myapp::OtherCurrent"
    })
    job = {}
    with_context("Myapp::Current", "user_id", 123) do
      with_context("Myapp::OtherCurrent", "other_id", 789) do
        cm.call(nil, job, nil, nil) do
          assert_equal 123, Serializer.deserialize(job["cattr"]).to_h[:user_id]
          assert_equal 789, Serializer.deserialize(job["cattr_1"]).to_h[:other_id]
        end
      end
    end

    with_context("Myapp::Current", :user_id, 456) do
      with_context("Myapp::OtherCurrent", :other_id, 999) do
        cm.call(nil, job, nil, nil) do
          assert_equal 123, Serializer.deserialize(job["cattr"]).to_h[:user_id]
          assert_equal 789, Serializer.deserialize(job["cattr_1"]).to_h[:other_id]
        end
      end
    end
  end

  def test_loads
    cm = Sidekiq::CurrentAttributes::Load.new({
      "cattr" => "Myapp::Current",
      "cattr_1" => "Myapp::OtherCurrent"
    })

    job = {"cattr" => {"user_id" => 123}, "cattr_1" => {"other_id" => 456}}
    assert_nil Myapp::Current.user_id
    assert_nil Myapp::OtherCurrent.other_id
    cm.call(nil, job, nil) do
      assert_equal 123, Myapp::Current.user_id
      assert_equal 456, Myapp::OtherCurrent.other_id
    end
    # the Rails reloader is responsible for resetting Current after every unit of work
  end

  def test_persists_with_class_argument
    Sidekiq::CurrentAttributes.persist("Myapp::Current", @config)
    job_hash = {}
    with_context("Myapp::Current", :user_id, 16) do
      @config.client_middleware.invoke(nil, job_hash, nil, nil) do
        assert_equal 16, Serializer.deserialize(job_hash["cattr"]).to_h[:user_id]
      end
    end

    #   assert_nil Myapp::Current.user_id
    #   Sidekiq.server_middleware.invoke(nil, job_hash, nil) do
    #     assert_equal 16, job_hash["cattr"][:user_id]
    #     assert_equal 16, Myapp::Current.user_id
    #   end
    #   assert_nil Myapp::Current.user_id
    # ensure
    #   Sidekiq.client_middleware.clear
    #   Sidekiq.server_middleware.clear
  end

  def test_persists_with_hash_argument
    cattrs = [Myapp::Current, "Myapp::OtherCurrent"]
    Sidekiq::CurrentAttributes.persist(cattrs, @config)
    job_hash = {}
    with_context("Myapp::Current", :user_id, 16) do
      with_context("Myapp::OtherCurrent", :other_id, 17) do
        @config.client_middleware.invoke(nil, job_hash, nil, nil) do
          assert_equal 16, Serializer.deserialize(job_hash["cattr"]).to_h[:user_id]
          assert_equal 17, Serializer.deserialize(job_hash["cattr_1"]).to_h[:other_id]
        end
      end
    end
  end

  def test_persists_after_perform_inline
    Sidekiq::CurrentAttributes.persist("Myapp::Current", @config)
    with_context("Myapp::Current", :user_id, 16) do
      assert_equal 16, Myapp::Current.user_id
      CurrentAttributesJob.perform_inline
      assert_equal 16, Myapp::Current.user_id
    end
  end

  def test_ignores_nonexistent_attributes
    cm = Sidekiq::CurrentAttributes::Load.new({
      "cattr" => "Myapp::Current"
    })

    job = {"cattr" => {"user_id" => 123, "non_existent" => 456}}
    assert_nil Myapp::Current.user_id
    cm.call(nil, job, nil) do
      assert_equal 123, Myapp::Current.user_id
    end
  end

  def test_doesnt_swallow_errors_raised_in_the_job
    cm = Sidekiq::CurrentAttributes::Load.new({
      "cattr" => "Myapp::Current"
    })

    job = {"cattr" => {"user_id" => 123}}
    assert_raises do
      first_time = true
      cm.call(nil, job, nil) do
        if first_time
          first_time = false
          raise nil.this_method_is_undefined
        end
      end
    end
  end

  private

  def with_context(strklass, attr, value)
    constklass = strklass.constantize
    constklass.send(:"#{attr}=", value)
    yield
  end
end
