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

      # Get metric data for all jobs from the last hour
      #  +class_filter+: return only results for classes matching filter
      #  +minutes+: the number of fine-grained minute buckets to retrieve
      #  +hours+: the number of coarser-grained 10-minute buckets to retrieve, in hours
      def top_jobs(class_filter: nil, minutes: nil, hours: nil)
        result = Result.new
        minutes = 60 unless minutes || hours
        count = hours ? hours * 6 : minutes
        time = @time
        minutely = ->(time) { "j|#{time.strftime("%y%m%d")}|#{time.hour}:#{time.min}" }
        tenly = ->(time) do
          m = time.min
          mins = (m < 10) ? "0" : m.to_s[0]
          "j|#{time.strftime("%y%m%d")}|#{time.hour}:#{mins}"
        end
        keyproc = minutes ? minutely : tenly
        advance = minutes ? 60 : 600

        redis_results = @pool.with do |conn|
          conn.pipelined do |pipe|
            count.times do |idx|
              key = keyproc.call(time)
              pipe.hgetall key
              result.prepend_bucket time
              time -= advance
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
          time -= advance
        end

        result.marks = fetch_marks(result.starts_at..result.ends_at)
        result
      end

      def for_job(klass, minutes: nil, hours: nil)
        result = Result.new
        minutes = 60 unless minutes || hours
        count = hours ? hours * 6 : minutes
        time = @time
        minutely = ->(time) { "j|#{time.strftime("%y%m%d")}|#{time.hour}:#{time.min}" }
        tenly = ->(time) do
          m = time.min
          mins = (m < 10) ? "0" : m.to_s[0]
          "j|#{time.strftime("%y%m%d")}|#{time.hour}:#{mins}"
        end
        keyproc = minutes ? minutely : tenly
        advance = minutes ? 60 : 600

        redis_results = @pool.with do |conn|
          conn.pipelined do |pipe|
            count.times do |idx|
              key = keyproc.call(time)
              pipe.hmget key, "#{klass}|ms", "#{klass}|p", "#{klass}|f"
              result.prepend_bucket time
              time -= advance
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
            time -= advance
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
          return 0 if completed.zero?
          totals[metric].to_f / completed
        end

        def series_avg(metric = "ms")
          series[metric].each_with_object(Hash.new(0)) do |(bucket, value), result|
            completed = series.dig("p", bucket) - series.dig("f", bucket)
            result[bucket] = (completed == 0) ? 0 : value.to_f / completed
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
