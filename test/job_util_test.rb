# frozen_string_literal: true

require_relative "helper"

class JobUtilHarness
  include Sidekiq::JobUtil
end

class JobUtilCustomQueueJob
  include Sidekiq::Job

  sidekiq_options "queue" => "custom_queue", "retry" => 5
end

class JobUtilWrapped
  def self.get_sidekiq_options
    {"queue" => "wrapped_queue"}
  end
end

class JobUtilPlainObject
end

describe Sidekiq::JobUtil do
  before do
    reset!
    @util = JobUtilHarness.new
  end

  describe "#validate" do
    it "accepts a minimal valid item" do
      @util.validate({"class" => "SomeJob", "args" => []})
    end

    it "requires a class key" do
      assert_raises(ArgumentError) { @util.validate({"args" => []}) }
    end

    it "requires an args key" do
      assert_raises(ArgumentError) { @util.validate({"class" => "SomeJob"}) }
    end

    it "requires the item to be a Hash" do
      assert_raises(ArgumentError) { @util.validate("nope") }
    end

    it "requires args to be an Array" do
      assert_raises(ArgumentError) { @util.validate({"class" => "SomeJob", "args" => "x"}) }
    end

    it "accepts a lazy enumerator for args" do
      lazy = [1, 2, 3].lazy
      @util.validate({"class" => "SomeJob", "args" => lazy})
    end

    it "accepts a Class or a String for class" do
      @util.validate({"class" => JobUtilCustomQueueJob, "args" => []})
      @util.validate({"class" => "SomeJob", "args" => []})
    end

    it "rejects a non-Class, non-String class" do
      assert_raises(ArgumentError) { @util.validate({"class" => 123, "args" => []}) }
    end

    it "requires at to be Numeric when present" do
      @util.validate({"class" => "SomeJob", "args" => [], "at" => 1.5})
      assert_raises(ArgumentError) { @util.validate({"class" => "SomeJob", "args" => [], "at" => "soon"}) }
    end

    it "requires tags to be an Array when present" do
      @util.validate({"class" => "SomeJob", "args" => [], "tags" => ["a"]})
      assert_raises(ArgumentError) { @util.validate({"class" => "SomeJob", "args" => [], "tags" => "a"}) }
    end

    it "rejects an absurdly large retry_for" do
      @util.validate({"class" => "SomeJob", "args" => [], "retry_for" => 1_000})
      assert_raises(ArgumentError) { @util.validate({"class" => "SomeJob", "args" => [], "retry_for" => 2_000_000_000}) }
    end
  end

  describe "#normalize_item" do
    it "generates a 24-character hex jid when absent" do
      item = @util.normalize_item({"class" => "SomeJob", "args" => []})
      assert_match(/\A[0-9a-f]{24}\z/, item["jid"])
    end

    it "preserves a provided jid" do
      item = @util.normalize_item({"class" => "SomeJob", "args" => [], "jid" => "abc123"})
      assert_equal "abc123", item["jid"]
    end

    it "stringifies the class and queue" do
      item = @util.normalize_item({"class" => JobUtilCustomQueueJob, "args" => []})
      assert_equal "JobUtilCustomQueueJob", item["class"]
      assert_instance_of String, item["queue"]
    end

    it "merges the job class sidekiq_options" do
      item = @util.normalize_item({"class" => JobUtilCustomQueueJob, "args" => []})
      assert_equal "custom_queue", item["queue"]
      assert_equal 5, item["retry"]
    end

    it "falls back to the default queue for a String class" do
      item = @util.normalize_item({"class" => "SomeJob", "args" => []})
      assert_equal "default", item["queue"]
    end

    it "honors a wrapped object's sidekiq_options" do
      item = @util.normalize_item({"class" => "Wrapper", "wrapped" => JobUtilWrapped, "args" => []})
      assert_equal "wrapped_queue", item["queue"]
    end

    it "raises when the queue is nil or empty" do
      assert_raises(ArgumentError) { @util.normalize_item({"class" => "SomeJob", "args" => [], "queue" => ""}) }
      assert_raises(ArgumentError) { @util.normalize_item({"class" => "SomeJob", "args" => [], "queue" => nil}) }
    end

    it "sets created_at when absent and preserves a provided value" do
      item = @util.normalize_item({"class" => "SomeJob", "args" => []})
      assert_instance_of Integer, item["created_at"]

      item = @util.normalize_item({"class" => "SomeJob", "args" => [], "created_at" => 123})
      assert_equal 123, item["created_at"]
    end

    it "coerces retry_for to an integer" do
      item = @util.normalize_item({"class" => "SomeJob", "args" => [], "retry_for" => 100.9})
      assert_equal 100, item["retry_for"]
    end

    it "raises for a bare Class that is not a Sidekiq::Job" do
      err = assert_raises(ArgumentError) { @util.normalize_item({"class" => String, "args" => []}) }
      assert_match(/must include a Sidekiq::Job class/, err.message)
    end
  end

  describe "#now_in_millis" do
    it "returns the current time in integer milliseconds" do
      now = @util.now_in_millis
      assert_instance_of Integer, now
      assert_in_delta(Time.now.to_f * 1000, now, 1000)
    end
  end

  describe "#json_unsafe?" do
    it "treats native JSON scalars as safe" do
      [1, 1.5, true, false, nil, "string"].each do |val|
        assert_nil @util.send(:json_unsafe?, val), "expected #{val.inspect} to be safe"
      end
    end

    it "treats nested arrays and hashes of safe values as safe" do
      assert_nil @util.send(:json_unsafe?, [1, "two", [3, [4]], {"k" => "v"}])
      assert_nil @util.send(:json_unsafe?, {"a" => [1, {"b" => 2}]})
    end

    it "flags a top-level symbol as unsafe" do
      assert_equal :sym, @util.send(:json_unsafe?, :sym)
    end

    it "flags a non-String hash key" do
      assert_equal 1, @util.send(:json_unsafe?, {1 => "a"})
    end

    it "flags a custom object" do
      obj = JobUtilPlainObject.new
      assert_same obj, @util.send(:json_unsafe?, [obj])
    end

    it "flags an unsafe value nested inside an array" do
      assert_equal :bad, @util.send(:json_unsafe?, [1, [2, :bad]])
    end

    it "flags an unsafe value nested inside a hash" do
      assert_equal :bad, @util.send(:json_unsafe?, {"a" => {"b" => :bad}})
    end
  end

  describe "#verify_json" do
    it "does not raise for native JSON arguments" do
      @util.verify_json({"class" => "SomeJob", "args" => [1, "two", {"k" => [3]}]})
    end

    it "raises for complex arguments under the default :raise mode" do
      err = assert_raises(ArgumentError) do
        @util.verify_json({"class" => "SomeJob", "args" => [:not_json]})
      end
      assert_match(/must be native JSON types/, err.message)
    end

    it "names the wrapped class in the error message" do
      err = assert_raises(ArgumentError) do
        @util.verify_json({"class" => "Wrapper", "wrapped" => "RealJob", "args" => [:nope]})
      end
      assert_match(/RealJob/, err.message)
    end

    it "warns instead of raising in :warn mode" do
      original = Sidekiq::Config::DEFAULTS[:on_complex_arguments]
      Sidekiq.strict_args!(:warn)
      assert_output(nil, /must be native JSON types/) do
        @util.verify_json({"class" => "SomeJob", "args" => [:not_json]})
      end
    ensure
      Sidekiq::Config::DEFAULTS[:on_complex_arguments] = original
    end

    it "does nothing when complex-argument checking is disabled" do
      original = Sidekiq::Config::DEFAULTS[:on_complex_arguments]
      Sidekiq.strict_args!(false)
      assert_silent do
        @util.verify_json({"class" => "SomeJob", "args" => [:not_json]})
      end
    ensure
      Sidekiq::Config::DEFAULTS[:on_complex_arguments] = original
    end
  end
end
