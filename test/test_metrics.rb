# frozen_string_literal: true

require_relative "helper"
require "sidekiq/component"
require "sidekiq/metrics/tracking"
require "sidekiq/metrics/query"
require "sidekiq/metrics/deploy"
require "sidekiq/api"

describe Sidekiq::Metrics do
  before do
    Sidekiq.redis { |c| c.flushdb }
  end

  def fixed_time
    @whence ||= Time.utc(2022, 7, 22, 22, 3, 0)
  end

  def create_known_metrics(time = fixed_time)
    smet = Sidekiq::Metrics::ExecutionTracker.new(Sidekiq)
    smet.track("critical", "App::SomeJob") { sleep 0.001 }
    smet.track("critical", "App::FooJob") { sleep 0.001 }
    assert_raises RuntimeError do
      smet.track("critical", "App::SomeJob") do
        raise "boom"
      end
    end
    smet.flush(time)
    smet.track("critical", "App::FooJob") { sleep 0.001 }
    smet.track("critical", "App::FooJob") { sleep 0.025 }
    smet.track("critical", "App::FooJob") { sleep 0.001 }
    smet.track("critical", "App::SomeJob") { sleep 0.001 }
    smet.flush(time - 60)
  end

  it "tracks metrics" do
    count = create_known_metrics
    assert_equal 12, count
  end

  describe "marx" do
    it "owns the means of production" do
      whence = Time.local(2022, 7, 17, 18, 43, 15)
      floor = whence.utc.rfc3339.sub(":15", ":00")

      d = Sidekiq::Metrics::Deploy.new
      d.mark(at: whence, label: "cafed00d - some git summary line")

      q = Sidekiq::Metrics::Query.new(now: whence)
      rs = q.for_job("FooJob")
      refute_nil rs[:marks]
      assert_equal 1, rs[:marks].size
      assert_equal "cafed00d - some git summary line", rs[:marks][floor], rs.inspect

      d = Sidekiq::Metrics::Deploy.new
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
      key = Sidekiq.redis do |conn|
        h.persist(conn, fixed_time)
      end
      assert_equal 0, h.sum
      refute_nil key
      assert_equal "App::FooJob-22-22:3", key

      h = Sidekiq::Metrics::Histogram.new("App::FooJob")
      data = Sidekiq.redis { |c| h.fetch(c, fixed_time) }
      {0 => 1, 3 => 3, 7 => 3, 25 => 1}.each_pair do |idx, val|
        assert_equal val, data[idx]
      end
    end
  end

  describe "querying" do
    it "handles empty metrics" do
      q = Sidekiq::Metrics::Query.new(now: fixed_time)
      result = q.top_jobs
      assert_equal 60, result.buckets.size
      assert_equal({}, result.job_results)

      q = Sidekiq::Metrics::Query.new(now: fixed_time)
      rs = q.for_job("DoesntExist")
      refute_nil rs
      assert_equal 7, rs.size
    end

    it "fetches top job data" do
      create_known_metrics
      q = Sidekiq::Metrics::Query.new(now: fixed_time)
      result = q.top_jobs
      assert_equal fixed_time - 59 * 60, result.starts_at
      assert_equal fixed_time, result.ends_at

      assert_equal 60, result.buckets.size
      assert_equal "21:04", result.buckets.first
      assert_equal "22:03", result.buckets.last

      assert_equal %w[App::SomeJob App::FooJob].sort, result.job_results.keys.sort
      some_job_result = result.job_results["App::SomeJob"]
      refute_nil some_job_result
      assert_equal %w[p f ms s].sort, some_job_result.series.keys.sort
      assert_equal %w[p f ms s].sort, some_job_result.totals.keys.sort
      assert_equal 2, some_job_result.series.dig("p", "22:03")
      assert_equal 3, some_job_result.totals["p"]
    end

    it "fetches job-specific data" do
      create_known_metrics
      d = Sidekiq::Metrics::Deploy.new
      d.mark(at: fixed_time - 300, label: "cafed00d - some git summary line")

      q = Sidekiq::Metrics::Query.new(now: fixed_time)
      rs = q.for_job("App::FooJob")
      assert_equal Date.new(2022, 7, 22), rs[:date]
      assert_equal 60, rs[:data].size
      assert_equal ["2022-07-22T21:58:00Z", "cafed00d - some git summary line"], rs[:marks].first

      data = rs[:data]
      assert_equal({time: "2022-07-22T22:03:00Z", p: 1, f: 0}, data[0].slice(:time, :p, :f))
      assert_equal({time: "2022-07-22T22:02:00Z", p: 3, f: 0}, data[1].slice(:time, :p, :f))
      assert_equal "cafed00d - some git summary line", data[5][:mark]

      # from create_known_data
      hist = data[1][:hist]
      assert_equal 2, hist[0]
      assert_equal 1, hist[1]
    end
  end
end
