require "sidekiq"
require "date"
require "set"

require "sidekiq/metrics/shared"

module Sidekiq
  module Metrics
    # Allows caller to query for Sidekiq execution metrics within Redis.
    # Caller sets a set of attributes to act as filters. {#fetch} will call
    # Redis and return a Hash of results.
    #
    # NB: all metrics and times/dates are UTC only. We specifically do not
    # support timezones.
    class Query
      # :hour, :day, :month
      attr_accessor :period

      # a specific job class, e.g. "App::OrderJob"
      attr_accessor :klass

      # the date specific to the period
      # for :day or :hour, something like Date.today or Date.new(2022, 7, 13)
      # for :month, Date.new(2022, 7, 1)
      attr_accessor :date

      # for period = :hour, the specific hour, integer e.g. 1 or 18
      # note that hours and minutes do not have a leading zero so minute-specific
      # keys will look like "j|20220718|7:3" for data at 07:03.
      attr_accessor :hour

      def initialize(pool: Sidekiq.redis_pool, now: Time.now)
        @time = now.utc
        @pool = pool
        @klass = nil
      end

      # Get metric data for all jobs from the last hour
      def top_jobs(minutes: 60)
        result = Result.new

        time = @time
        redis_results = @pool.with do |conn|
          conn.pipelined do |pipe|
            minutes.times do |idx|
              key = "j|#{time.strftime("%Y%m%d")}|#{time.hour}:#{time.min}"
              pipe.hgetall key
              result.prepend_bucket time
              time -= 60
            end
          end
        end

        time = @time
        redis_results.each do |hash|
          hash.each do |k, v|
            kls, metric = k.split("|")
            result.job_results[kls].add_metric metric, time, v.to_i
          end
          time -= 60
        end

        result.marks = fetch_marks(result.starts_at..result.ends_at)

        result
      end

      def for_job(klass, minutes: 60)
        result = Result.new

        time = @time
        redis_results = @pool.with do |conn|
          conn.pipelined do |pipe|
            minutes.times do |idx|
              key = "j|#{time.strftime("%Y%m%d")}|#{time.hour}:#{time.min}"
              pipe.hmget key, "#{klass}|ms", "#{klass}|p", "#{klass}|f"
              result.prepend_bucket time
              time -= 60
            end
          end
        end

        time = @time
        @pool.with do |conn|
          redis_results.each do |(ms, p, f)|
            result.job_results[klass].add_metric "ms", time, ms.to_i if ms
            result.job_results[klass].add_metric "p", time, p.to_i if p
            result.job_results[klass].add_metric "f", time, f.to_i if f
            result.job_results[klass].add_hist time, Histogram.new(klass).fetch(conn, time)
            time -= 60
          end
        end

        result.marks = fetch_marks(result.starts_at..result.ends_at)

        result
      end

      class Result < Struct.new(:starts_at, :ends_at, :size, :buckets, :job_results, :marks)
        def initialize
          super
          self.buckets = []
          self.marks = []
          self.job_results = Hash.new { |h, k| h[k] = JobResult.new }
        end

        def prepend_bucket(time)
          buckets.unshift time.strftime("%H:%M")
          self.ends_at ||= time
          self.starts_at = time
        end
      end

      class JobResult < Struct.new(:series, :hist, :totals)
        def initialize
          super
          self.series = Hash.new { |h, k| h[k] = Hash.new(0) }
          self.hist = Hash.new { |h, k| h[k] = [] }
          self.totals = Hash.new(0)
        end

        def add_metric(metric, time, value)
          totals[metric] += value
          series[metric][time.strftime("%H:%M")] += value

          # Include timing measurements in seconds for convenience
          add_metric("s", time, value / 1000.0) if metric == "ms"
        end

        def add_hist(time, hist_result)
          hist[time.strftime("%H:%M")] = hist_result
        end

        def total_avg(metric = "ms")
          completed = totals["p"] - totals["f"]
          totals[metric].to_f / completed
        end

        def series_avg(metric = "ms")
          series[metric].each_with_object(Hash.new(0)) do |(bucket, value), result|
            completed = series.dig("p", bucket) - series.dig("f", bucket)
            result[bucket] = completed == 0 ? 0 : value.to_f / completed
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
