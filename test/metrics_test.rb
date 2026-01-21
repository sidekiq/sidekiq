# frozen_string_literal: true

require_relative "helper"
require "sidekiq/component"
require "sidekiq/metrics/tracking"
require "sidekiq/metrics/query"
require "sidekiq/job_retry"
require "sidekiq/deploy"
require "sidekiq/api"

describe Sidekiq::Metrics do
  before do
    @config = reset!
  end

  def fixed_time
    @whence ||= Time.utc(2022, 7, 22, 22, 3, 0)
  end

  
  def create_known_metrics(time = fixed_time)
    smet = Sidekiq::Metrics::ExecutionTracker.new(@config)
    # Use deterministic timing by stubbing mono_ms to avoid flaky tests
    # mono_ms is called twice per track: once for start, once for finish
    # time_ms = finish - start, so we control the difference
    # Sequence: [start1, finish1, start2, finish2, ...]
    # Each pair (start, finish) determines execution time
    mono_times = [
      0, 1,     # App::SomeJob: 1ms
      2, 3,     # App::FooJob: 1ms
      4, 5,     # App::SomeJob (raises): 1ms
      # flush(time)
      6, 7,     # App::FooJob: 1ms  -> bucket 0 (<20ms)
      8, 28,    # App::FooJob: 20ms -> bucket 1 (20-30ms)
      29, 30,   # App::FooJob: 1ms  -> bucket 0 (<20ms)
      31, 32,   # App::SomeJob: 1ms
      # flush(time - 60)
      33, 53,   # App::FooJob: 20ms -> bucket 1
      54, 55,   # App::FooJob: 1ms  -> bucket 0
      56, 57    # App::SomeJob: 1ms
      # flush(time - 6000)
    ].each
    smet.stub(:mono_ms, -> { mono_times.next }) do
      smet.track("critical", "App::SomeJob") { }
      smet.track("critical", "App::FooJob") { }
      assert_raises RuntimeError do
        smet.track("critical", "App::SomeJob") do
          raise "boom"
        end
      end
      smet.flush(time)
      smet.track("critical", "App::FooJob") { }
      smet.track("critical", "App::FooJob") { }
      smet.track("critical", "App::FooJob") { }
      smet.track("critical", "App::SomeJob") { }
      smet.flush(time - 60)
      smet.track("critical", "App::FooJob") { }
      smet.track("critical", "App::FooJob") { }
      smet.track("critical", "App::SomeJob") { }
      smet.flush(time - 6000)
    end
  end
  
  it "tracks metrics" do
    count = create_known_metrics
    assert_equal 8, count
  end

  it "does not track failures for interrupted iterable jobs" do
    smet = Sidekiq::Metrics::ExecutionTracker.new(@config)
    assert_raises Sidekiq::JobRetry::Skip do
      smet.track("critical", "App::SomeJob") do
        sleep 0.001
        raise Sidekiq::JobRetry::Skip
      end
    end
    smet.flush(fixed_time)

    q = Sidekiq::Metrics::Query.new(now: fixed_time)
    result = q.for_job("App::SomeJob")
    job_result = result.job_results["App::SomeJob"]
    refute_equal 0, job_result.totals["ms"]
    assert_equal 1, job_result.totals["p"]
    assert_equal 0, job_result.totals["f"]
  end

  describe "marx" do
    it "owns the means of production" do
      whence = Time.local(2022, 7, 17, 18, 43, 15)
      floor = whence.utc.iso8601.sub(":15", ":00")

      d = Sidekiq::Deploy.new
      d.mark!(at: whence, label: "cafed00d - some git summary line")
      d.mark!(at: whence)

      q = Sidekiq::Metrics::Query.new(now: whence)
      rs = q.for_job("FooJob")
      refute_nil rs.marks
      assert_equal 1, rs.marks.size
      assert_equal "cafed00d - some git summary line", rs.marks.first.label, rs.marks.inspect

      d = Sidekiq::Deploy.new
      rs = d.fetch(whence)
      refute_nil rs
      assert_equal 1, rs.size
      assert_equal "cafed00d - some git summary line", rs[floor]
    end
  end

  describe "histograms" do
    it "buckets a bunch of times" do
      h = Sidekiq::Metrics::Histogram.new("App::FooJob")
      assert_equal 0, h.sum
      h.record_time(10)
      h.record_time(46)
      h.record_time(47)
      h.record_time(48)
      h.record_time(300)
      h.record_time(301)
      h.record_time(302)
      h.record_time(300000000)
      assert_equal 8, h.sum
      key = @config.redis do |conn|
        h.persist(conn, fixed_time)
      end
      assert_equal 0, h.sum
      refute_nil key
      assert_equal "h|App::FooJob-22-22:3", key

      h = Sidekiq::Metrics::Histogram.new("App::FooJob")
      data = @config.redis { |c| h.fetch(c, fixed_time) }
      {0 => 1, 3 => 3, 7 => 3, 25 => 1}.each_pair do |idx, val|
        assert_equal val, data[idx]
      end
    end
  end

  describe "querying" do
    it "handles empty metrics" do
      q = Sidekiq::Metrics::Query.new(now: fixed_time)
      result = q.top_jobs
      assert_equal([], result.job_results.keys)

      q = Sidekiq::Metrics::Query.new(now: fixed_time)
      result = q.for_job("DoesntExist")
      assert_equal(["DoesntExist"], result.job_results.keys)
    end

    it "filters top job data" do
      create_known_metrics

      q = Sidekiq::Metrics::Query.new(now: fixed_time)
      result = q.top_jobs(class_filter: /some/i)
      assert_equal fixed_time - 60 * 60, result.starts_at
      assert_equal fixed_time, result.ends_at

      assert_equal %w[App::SomeJob].sort, result.job_results.keys.sort
      job_result = result.job_results["App::SomeJob"]
      refute_nil job_result
    end

    it "fetches top job data" do
      create_known_metrics
      d = Sidekiq::Deploy.new
      d.mark!(at: fixed_time - 300, label: "cafed00d - some git summary line")

      q = Sidekiq::Metrics::Query.new(now: fixed_time)
      result = q.top_jobs
      assert_equal fixed_time - 60 * 60, result.starts_at
      assert_equal fixed_time, result.ends_at
      assert_equal 1, result.marks.size
      assert_equal "cafed00d - some git summary line", result.marks[0].label
      assert_equal "2022-07-22T21:58:00Z", result.marks[0].bucket

      assert_equal %w[App::SomeJob App::FooJob].sort, result.job_results.keys.sort
      job_result = result.job_results["App::SomeJob"]
      refute_nil job_result
      assert_equal %w[p f ms s].sort, job_result.series.keys.sort
      assert_equal %w[p f ms s].sort, job_result.totals.keys.sort
      assert_equal 2, job_result.series.dig("p", "2022-07-22T22:03:00Z")
      assert_equal 3, job_result.totals["p"]
      # Execution time is not consistent, so these assertions are not exact
      assert job_result.total_avg("ms").between?(0.5, 2), job_result.total_avg("ms")
      assert job_result.series_avg("s")["2022-07-22T22:03:00Z"].between?(0.0005, 0.002), job_result.series_avg("s")

      q = Sidekiq::Metrics::Query.new(now: fixed_time)
      result = q.top_jobs(hours: 24)
      assert_equal :hourly, result.granularity
      assert result.job_results["App::SomeJob"]
      assert_equal({"2022-07-22T22:00:00Z" => 3, "2022-07-22T20:20:00Z" => 1}, result.job_results["App::SomeJob"].series["p"])
      assert_equal 1, result.marks.size
      assert_equal "cafed00d - some git summary line", result.marks[0].label
      assert_equal "2022-07-22T21:50:00Z", result.marks[0].bucket
    end

    it "fetches job-specific data" do
      create_known_metrics
      d = Sidekiq::Deploy.new
      d.mark!(at: fixed_time - 300, label: "cafed00d - some git summary line")

      q = Sidekiq::Metrics::Query.new(now: fixed_time)
      result = q.for_job("App::FooJob")
      assert_equal fixed_time - 60 * 60, result.starts_at
      assert_equal fixed_time, result.ends_at
      assert_equal 1, result.marks.size
      assert_equal "cafed00d - some git summary line", result.marks[0].label
      assert_equal "2022-07-22T21:58:00Z", result.marks[0].bucket

      # from create_known_data
      assert_equal %w[App::FooJob], result.job_results.keys
      job_result = result.job_results["App::FooJob"]
      refute_nil job_result
      assert_equal %w[p ms s].sort, job_result.series.keys.sort
      assert_equal %w[p ms s].sort, job_result.totals.keys.sort
      assert_equal 1, job_result.series.dig("p", "2022-07-22T22:03:00Z")
      assert_equal 4, job_result.totals["p"]
      assert_equal 2, job_result.hist.dig("2022-07-22T22:02:00Z", -1)
      assert_equal 1, job_result.hist.dig("2022-07-22T22:02:00Z", -2)

      q = Sidekiq::Metrics::Query.new(now: fixed_time)
      result = q.for_job("App::FooJob", hours: 24)
      assert_equal :hourly, result.granularity
      assert result.job_results["App::FooJob"]
      assert_equal({"2022-07-22T22:00:00Z" => 4, "2022-07-22T20:20:00Z" => 2}, result.job_results["App::FooJob"].series["p"])
    end
  end
end
