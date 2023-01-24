require_relative "helper"

describe Sidekiq::Deprecation do
  before do
    @config = reset!

    Sidekiq::Deprecation.behavior = nil
  end

  describe "behaviors" do
    it "can use the logger" do
      Sidekiq::Deprecation.behavior = :log
      caller_line = __LINE__ + 2 # the line the handle_deprecation is on
      output = capture_logging(@config) do
        Sidekiq::Deprecation.warn "everything!"
      end

      assert_includes output, "DEPRECATION(sidekiq): everything!"
      assert_includes output, "called from #{__FILE__}:#{caller_line}"
    end

    it "can be silenced" do
      Sidekiq::Deprecation.behavior = :silence
      caller_line = __LINE__ + 2 # the line the handle_deprecation is on
      output = capture_logging(@config) do
        Sidekiq::Deprecation.warn "this thing here"
      end

      refute_includes output, "DEPRECATION WARNING: this thing here"
    end

    it "can be assigned a proc or other object that responds to call" do
      Sidekiq::Deprecation.behavior = proc {|msg, ctx, caller|
        raise "DEPRECATION ERROR: #{msg}"
      }

      assert_raises RuntimeError, "DEPRECATION ERROR: this thing here" do
        Sidekiq::Deprecation.warn "this thing here"
      end
    end
  end

  describe ".warn" do
    it "can specify a different gem" do
      output = capture_logging(@config) do
        Sidekiq::Deprecation.warn("this method is being removed", gem_name: "sidekiq-awesome")
      end

      assert_includes output, "DEPRECATION(sidekiq-awesome): this method is being removed"
    end

    it "can specify a deprecation horizon" do
      output = capture_logging(@config) do
        Sidekiq::Deprecation.warn("this method is being removed", deprecation_horizon: "9000.0")
      end

      assert_includes output, "DEPRECATION(sidekiq-9000.0): this method is being removed"
    end
  end
end

