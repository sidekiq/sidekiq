# frozen_string_literal: true

require_relative "helper"
require "sidekiq/monitor"

def capture_stdout
  $stdout = StringIO.new
  yield
  $stdout.string.chomp
ensure
  $stdout = STDOUT
end

def output(section = "all")
  capture_stdout do
    Sidekiq::Monitor::Status.new.display(section)
  end
end

describe Sidekiq::Monitor do
  before do
    @config = reset!
  end

  describe "status" do
    describe "version" do
      it "displays the current Sidekiq version" do
        assert_includes output, "Sidekiq #{Sidekiq::VERSION}"
      end

      it "displays the current time" do
        Time.stub(:now, Time.at(0)) do
          assert_includes output, Time.at(0).utc.to_s
        end
      end
    end

    describe "overview" do
      it "has a heading" do
        assert_includes output, "---- Overview ----"
      end

      it "displays the correct output" do
        stats_attributes = {
          processed: 420710,
          failed: 12,
          workers_size: 34,
          enqueued: 56,
          retry_size: 78,
          scheduled_size: 90,
          dead_size: 666
        }
        mock_stats = Struct.new(*stats_attributes.keys).new(*stats_attributes.values)
        Sidekiq::Stats.stub(:new, mock_stats) do
          assert_includes output, "Processed: 420,710"
          assert_includes output, "Failed: 12"
          assert_includes output, "Busy: 34"
          assert_includes output, "Enqueued: 56"
          assert_includes output, "Retries: 78"
          assert_includes output, "Scheduled: 90"
          assert_includes output, "Dead: 666"
        end
      end
    end

    describe "processes" do
      it "has a heading" do
        assert_includes output, "---- Processes (0) ----"
      end

      it "displays the correct output" do
        mock_processes = [{
          "identity" => "foobar",
          "tag" => "baz",
          "started_at" => Time.now,
          "concurrency" => 5,
          "busy" => 2,
          "capsules" => {"mike" => {"weights" => {"low" => 1, "default" => 2, "high" => 3}},
                         "single" => {"weights" => {"single" => 0}}}
        }]
        Sidekiq::ProcessSet.stub(:new, mock_processes) do
          assert_includes output, "foobar [baz]"
          assert_includes output, "Started: #{mock_processes.first["started_at"]} (just now)"
          assert_includes output, "Threads: 5 (2 busy)"
          assert_includes output, "Queues: low, default, high; single"
        end
      end
    end

    describe "queues" do
      it "has a heading" do
        assert_includes output, "---- Queues (0) ----"
      end

      it "displays the correct output" do
        queue_struct = Struct.new(:name, :size, :latency)
        mock_queues = [
          queue_struct.new("foobar", 12, 12.3456),
          queue_struct.new("a_long_queue_name", 234, 567.89999)
        ]
        Sidekiq::Queue.stub(:all, mock_queues) do
          assert_includes output, "NAME                 SIZE  LATENCY"
          assert_includes output, "foobar                 12    12.35"
          assert_includes output, "a_long_queue_name     234   567.90"
        end
      end
    end

    describe "display" do
      it "reports an unknown section and lists valid ones" do
        out = output("bogus")
        assert_includes out, "I don't know how to check the status of 'bogus'!"
        assert_includes out, "all, version, overview, processes, queues"
      end
    end

    describe "helpers" do
      before do
        @status = Sidekiq::Monitor::Status.new
      end

      describe "#delimit" do
        it "inserts thousands separators" do
          assert_equal "0", @status.send(:delimit, 0)
          assert_equal "999", @status.send(:delimit, 999)
          assert_equal "1,000", @status.send(:delimit, 1_000)
          assert_equal "1,234,567", @status.send(:delimit, 1_234_567)
        end
      end

      describe "#split_multiline" do
        it "returns 'none' when values is nil" do
          assert_equal "none", @status.send(:split_multiline, nil)
        end

        it "joins short values onto a single line" do
          assert_equal "a; b; c", @status.send(:split_multiline, %w[a b c])
        end

        it "wraps onto subsequent lines when max_length is exceeded" do
          out = @status.send(:split_multiline, %w[aaaa bbbb cccc], max_length: 10, pad: 2)
          lines = out.split("\n")
          assert_operator lines.size, :>=, 2
          assert lines[1..].all? { |l| l.start_with?("  ") }, "padded continuation lines"
        end
      end

      describe "#tags_for" do
        it "returns nil when there are no tags" do
          assert_nil @status.send(:tags_for, "tag" => nil, "labels" => nil, "quiet" => "false")
        end

        it "formats tag, labels, and a quiet marker" do
          formatted = @status.send(:tags_for, "tag" => "web", "labels" => ["fast", "infra"], "quiet" => "true")
          assert_equal "[web] [fast] [infra] [quiet]", formatted
        end

        it "omits the quiet marker when the process is not quiet" do
          formatted = @status.send(:tags_for, "tag" => "web", "labels" => nil, "quiet" => "false")
          assert_equal "[web]", formatted
        end
      end

      describe "#time_ago" do
        it "returns 'just now' for timestamps under a minute old" do
          assert_equal "just now", @status.send(:time_ago, Time.now.to_f - 30)
        end

        it "returns 'a minute ago' between 60 and 120 seconds" do
          assert_equal "a minute ago", @status.send(:time_ago, Time.now.to_f - 90)
        end

        it "returns 'N minutes ago' under an hour" do
          assert_equal "10 minutes ago", @status.send(:time_ago, Time.now.to_f - 600)
        end

        it "returns 'an hour ago' between 1 and 2 hours" do
          assert_equal "an hour ago", @status.send(:time_ago, Time.now.to_f - 3700)
        end

        it "returns 'N hours ago' beyond two hours" do
          assert_equal "3 hours ago", @status.send(:time_ago, Time.now.to_f - 3 * 3600)
        end
      end
    end
  end
end
