# frozen_string_literal: true

require "date"
require "sidekiq"
require "sidekiq/metrics/shared"

module Sidekiq
  module Metrics
    # Allows caller to query for Sidekiq execution metrics within Redis.
    # Caller sets a set of attributes to act as filters. {#fetch} will call
    # Redis and return a Hash of results.
    #
    # NB: all metrics and times/dates are UTC only. We explicitly do not
    # support timezones.
    class Query
      def initialize(pool: nil, now: Time.now)
        @time = now.utc
        @pool = pool || Sidekiq.default_configuration.redis_pool
        @klass = nil
      end

      ROLLUPS = {
        # minutely aggregates per minute
        minutely: [60, ->(time) { time.strftime("j|%y%m%d|%-H:%M") }],
        # hourly aggregates every 10 minutes so we'll have six data points per hour
        hourly: [600, ->(time) {
          m = time.min
          mins = (m < 10) ? "0" : m.to_s[0]
          time.strftime("j|%y%m%d|%-H:#{mins}")
        }]
      }

      # Get metric data for all jobs from the last hour
      #  +class_filter+: return only results for classes matching filter
      #  +minutes+: the number of fine-grained minute buckets to retrieve
      #  +hours+: the number of coarser-grained 10-minute buckets to retrieve, in hours
      def top_jobs(class_filter: nil, minutes: nil, hours: nil)
        time = @time
        result = Result.new(hours ? :hourly : :minutely)
        minutes = 60 unless minutes || hours
        rollup = hours ? :hourly : :minutely
        count = hours ? hours * 6 : minutes
        stride, keyproc = ROLLUPS[rollup]

        redis_results = @pool.with do |conn|
          conn.pipelined do |pipe|
            count.times do |idx|
              key = keyproc.call(time)
              pipe.hgetall key
              result.prepend_bucket time
              time -= stride
            end
          end
        end

        time = @time
        redis_results.each do |hash|
          hash.each do |k, v|
            kls, metric = k.split("|")
            next if class_filter && !class_filter.match?(kls)
            result.job_results[kls].add_metric metric, time, v.to_i
          end
          time -= stride
        end

        result.marks = fetch_marks(result.starts_at..result.ends_at)
        result
      end

      def for_job(klass, minutes: nil, hours: nil)
        time = @time
        minutes = 60 unless minutes || hours
        result = Result.new(hours ? :hourly : :minutely)
        rollup = hours ? :hourly : :minutely
        count = hours ? hours * 6 : minutes
        stride, keyproc = ROLLUPS[rollup]

        redis_results = @pool.with do |conn|
          conn.pipelined do |pipe|
            count.times do |idx|
              key = keyproc.call(time)
              pipe.hmget key, "#{klass}|ms", "#{klass}|p", "#{klass}|f"
              result.prepend_bucket time
              time -= stride
            end
          end
        end

        time = @time
        @pool.with do |conn|
          redis_results.each do |(ms, p, f)|
            result.job_results[klass].add_metric "ms", time, ms.to_i if ms
            result.job_results[klass].add_metric "p", time, p.to_i if p
            result.job_results[klass].add_metric "f", time, f.to_i if f
            result.job_results[klass].add_hist time, Histogram.new(klass).fetch(conn, time).reverse if minutes
            time -= stride
          end
        end

        result.marks = fetch_marks(result.starts_at..result.ends_at)
        result
      end

      class Result < Struct.new(:granularity, :starts_at, :ends_at, :size, :buckets, :job_results, :marks)
        def initialize(granularity = :minutely)
          super
          self.granularity = granularity
          self.buckets = []
          self.marks = []
          self.job_results = Hash.new { |h, k| h[k] = JobResult.new(granularity) }
        end

        def prepend_bucket(time)
          buckets.unshift bkt_time_s(time)
          self.ends_at ||= time
          self.starts_at = time
        end

        def bkt_time_s(time)
          # hourly buckets should be rounded to ten ("8:40", not "8:43")
          # and include day
          if granularity == :hourly
            time.strftime("%d %-H:%M").tap do |s|
              s[-1] = "0"
            end
          else
            time.strftime("%-H:%M")
          end
        end
      end

      class JobResult < Struct.new(:granularity, :series, :hist, :totals)
        def initialize(granularity = :minutely)
          super
          self.granularity = granularity
          self.series = Hash.new { |h, k| h[k] = Hash.new(0) }
          self.hist = Hash.new { |h, k| h[k] = [] }
          self.totals = Hash.new(0)
        end

        def add_metric(metric, time, value)
          totals[metric] += value
          series[metric][bkt_time_s(time)] += value

          # Include timing measurements in seconds for convenience
          add_metric("s", time, value / 1000.0) if metric == "ms"
        end

        def add_hist(time, hist_result)
          hist[bkt_time_s(time)] = hist_result
        end

        def total_avg(metric = "ms")
          completed = totals["p"] - totals["f"]
          return 0 if completed.zero?
          totals[metric].to_f / completed
        end

        def series_avg(metric = "ms")
          series[metric].each_with_object(Hash.new(0)) do |(bucket, value), result|
            completed = series.dig("p", bucket) - series.dig("f", bucket)
            result[bucket] = (completed == 0) ? 0 : value.to_f / completed
          end
        end

        def bkt_time_s(time)
          if granularity == :hourly
            # hourly buckets should be rounded to ten ("8:40", not "8:43")
            time.strftime("%d %H:%M").tap do |s|
              s[-1] = "0"
            end
          else
            time.strftime("%H:%M")
          end
        end
      end

      class MarkResult < Struct.new(:time, :label)
        def bucket
          time.strftime("%H:%M")
        end
      end

      private

      def fetch_marks(time_range)
        [].tap do |result|
          marks = @pool.with { |c| c.hgetall("#{@time.strftime("%Y%m%d")}-marks") }

          marks.each do |timestamp, label|
            time = Time.parse(timestamp)
            if time_range.cover? time
              result << MarkResult.new(time, label)
            end
          end
        end
      end
    end
  end
end
