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

      # Get metric data from the last hour and roll it up
      # into top processed count and execution time based on class.
      def top_jobs
        resultset = {}
        resultset[:date] = @time.to_date
        resultset[:period] = :hour
        resultset[:ends_at] = @time
        time = @time

        results = @pool.with do |conn|
          conn.pipelined do |pipe|
            resultset[:size] = 60
            60.times do |idx|
              key = "j|#{time.strftime("%Y%m%d")}|#{time.hour}:#{time.min}"
              pipe.hgetall key
              time -= 60
            end
            resultset[:starts_at] = time
          end
        end

        t = Hash.new(0)
        klsset = Set.new
        # merge the per-minute data into a totals hash for the hour
        results.each do |hash|
          hash.each { |k, v| t[k] = t[k] + v.to_i }
          klsset.merge(hash.keys.map { |k| k.split("|")[0] })
        end
        resultset[:job_classes] = klsset.delete_if { |item| item.size < 3 }
        resultset[:totals] = t
        top = t.each_with_object({}) do |(k, v), memo|
          (kls, metric) = k.split("|")
          memo[metric] ||= Hash.new(0)
          memo[metric][kls] = v
        end

        sorted = {}
        top.each_pair do |metric, hash|
          sorted[metric] = hash.sort_by { |k, v| v }.reverse.to_h
        end
        resultset[:top_classes] = sorted
        resultset
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
            {
              time: Time.utc(time.year, time.month, time.mday, time.hour, time.min, 0).rfc3339,
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
    end
  end
end
