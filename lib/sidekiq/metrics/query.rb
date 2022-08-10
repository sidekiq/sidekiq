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
        results = @pool.with do |conn|
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
        results.each do |hash|
          hash.each do |k, v|
            kls, metric = k.split("|")
            result.job_results[kls].add_metric metric, time, v.to_i
          end
          time -= 60
        end

        result
      end

      def for_job(klass)
        resultset = {}
        resultset[:date] = @time.to_date
        resultset[:period] = :hour
        resultset[:ends_at] = @time
        marks = @pool.with { |c| c.hgetall("#{@time.strftime("%Y%m%d")}-marks") }

        time = @time
        initial = @pool.with do |conn|
          conn.pipelined do |pipe|
            resultset[:size] = 60
            60.times do |idx|
              key = "j|#{time.strftime("%Y%m%d|%-H:%-M")}"
              pipe.hmget key, "#{klass}|ms", "#{klass}|p", "#{klass}|f"
              time -= 60
            end
          end
        end

        time = @time
        hist = Histogram.new(klass)
        results = @pool.with do |conn|
          initial.map do |(ms, p, f)|
            tm = Time.utc(time.year, time.month, time.mday, time.hour, time.min, 0)
            {
              time: tm.iso8601,
              epoch: tm.to_i,
              ms: ms.to_i, p: p.to_i, f: f.to_i, hist: hist.fetch(conn, time)
            }.tap { |x|
              x[:mark] = marks[x[:time]] if marks[x[:time]]
              time -= 60
            }
          end
        end

        resultset[:marks] = marks
        resultset[:starts_at] = time
        resultset[:data] = results
        resultset
      end

      class Result < Struct.new(:starts_at, :ends_at, :size, :buckets, :job_results)
        def initialize
          super
          self.buckets = []
          self.job_results = Hash.new { |h,k| h[k] = JobResult.new }
        end

        def prepend_bucket(time)
          buckets.unshift time.strftime("%H:%M")
          self.ends_at ||= time
          self.starts_at = time
        end
      end

      class JobResult < Struct.new(:series, :totals)
        def initialize
          super
          self.series = Hash.new { |h,k| h[k] = {} }
          self.totals = Hash.new(0)
        end

        def add_metric(metric, time, value)
          totals[metric] += value
          series[metric][time.strftime("%H:%M")] = value
        end
      end
    end
  end
end
