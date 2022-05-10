# frozen_string_literal: true

require_relative "helper"
require "sidekiq/cli"

describe Sidekiq do
  describe "json processing" do
    it "handles json" do
      assert_equal({"foo" => "bar"}, Sidekiq.load_json("{\"foo\":\"bar\"}"))
      assert_equal "{\"foo\":\"bar\"}", Sidekiq.dump_json({"foo" => "bar"})
    end
  end

  describe "redis connection" do
    it "returns error without creating a connection if block is not given" do
      assert_raises(ArgumentError) do
        Sidekiq.redis
      end
    end
  end

  describe "❨╯°□°❩╯︵┻━┻" do
    before { $stdout = StringIO.new }
    after { $stdout = STDOUT }

    it "allows angry developers to express their emotional constitution and remedies it" do
      Sidekiq.❨╯°□°❩╯︵┻━┻
      assert_equal "Calm down, yo.\n", $stdout.string
    end
  end

  describe "lifecycle events" do
    it "handles invalid input" do
      Sidekiq.options[:lifecycle_events][:startup].clear

      e = assert_raises ArgumentError do
        Sidekiq.on(:startp)
      end
      assert_match(/Invalid event name/, e.message)
      e = assert_raises ArgumentError do
        Sidekiq.on("startup")
      end
      assert_match(/Symbols only/, e.message)
      Sidekiq.on(:startup) do
        1 + 1
      end

      assert_equal 2, Sidekiq.options[:lifecycle_events][:startup].first.call
    end
  end

  describe "default_job_options" do
    it "stringifies keys" do
      @old_options = Sidekiq.default_job_options
      begin
        Sidekiq.default_job_options = {queue: "cat"}
        assert_equal "cat", Sidekiq.default_job_options["queue"]
      ensure
        Sidekiq.default_job_options = @old_options
      end
    end
  end

  describe "error handling" do
    it "deals with user-specified error handlers which raise errors" do
      output = capture_logging do
        Sidekiq.error_handlers << proc { |x, hash|
          raise "boom"
        }
        cli = Sidekiq::CLI.new
        cli.handle_exception(RuntimeError.new("hello"))
      ensure
        Sidekiq.error_handlers.pop
      end
      assert_includes output, "boom"
      assert_includes output, "ERROR"
    end
  end

  describe "redis connection" do
    it "does not continually retry" do
      assert_raises Redis::CommandError do
        Sidekiq.redis do |c|
          raise Redis::CommandError, "READONLY You can't write against a replica."
        end
      end
    end

    it "reconnects if connection is flagged as readonly" do
      counts = []
      Sidekiq.redis do |c|
        counts << c.info["total_connections_received"].to_i
        raise Sidekiq::RedisConnection.adapter::CommandError, "READONLY You can't write against a replica." if counts.size == 1
      end
      assert_equal 2, counts.size
      assert_equal counts[0] + 1, counts[1]
    end

    it "reconnects if instance state changed" do
      counts = []
      Sidekiq.redis do |c|
        counts << c.info["total_connections_received"].to_i
        raise Sidekiq::RedisConnection.adapter::CommandError, "UNBLOCKED force unblock from blocking operation, instance state changed (master -> replica?)" if counts.size == 1
      end
      assert_equal 2, counts.size
      assert_equal counts[0] + 1, counts[1]
    end
  end

  describe "redis info" do
    it "calls the INFO command which returns at least redis_version" do
      output = Sidekiq.redis_info
      assert_includes output.keys, "redis_version"
    end
  end
end
