# frozen_string_literal: true

require_relative "helper"
require "sidekiq/web"

describe Sidekiq::Web::Action do
  before { reset! }

  def action_with_session(session = {})
    Sidekiq::Web::Action.new({"rack.session" => session}, nil)
  end

  describe "#flash" do
    it "stores the block's return value under :skq_flash in the session" do
      session = {}
      action_with_session(session).flash { "saved" }
      assert_equal "saved", session[:skq_flash]
    end
  end

  describe "#flash?" do
    it "returns the stored flash value" do
      assert_equal "msg", action_with_session({skq_flash: "msg"}).flash?
    end

    it "returns nil when no flash is set" do
      assert_nil action_with_session.flash?
    end
  end

  describe "#get_flash" do
    it "returns the flash, deletes it from the session, and memoizes for subsequent reads" do
      session = {skq_flash: "once"}
      action = action_with_session(session)

      assert_equal "once", action.get_flash
      assert_nil session[:skq_flash], "expected get_flash to delete the session entry"
      assert_equal "once", action.get_flash, "expected subsequent reads to return the memoized value"
    end
  end
end
