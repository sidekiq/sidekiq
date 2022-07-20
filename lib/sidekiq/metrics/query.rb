require "sidekiq"
require "date"
require "set"

module Sidekiq
  module Metrics
    # Allows caller to query for Sidekiq execution metrics within Redis.
    # Caller sets a set of attributes to act as filters. {#fetch} will call
    # Redis and return a Hash of results.
    #
    # NB: all metrics and times/dates are UTC only. We specifically do not
    # support timezones.
    class Query
      # "job" or "queue"
      attr_accessor :type

      # :hour, :day, :month
      attr_accessor :period

      # a specific job class, e.g. "App::OrderJob"
      attr_accessor :klass

      # a specific queue name, e.g. "default"
      attr_accessor :queue

      # the date specific to the period
      # for :day or :hour, something like Date.today or Date.new(2022, 7, 13)
      # for :month, Date.new(2022, 7, 1)
      attr_accessor :date

      # for period = :hour, the specific hour, integer e.g. 1 or 18
      # note that hours and minutes do not have a leading zero so minute-specific
      # keys will look like "20220718|7:3" for data at 07:03.
      attr_accessor :hour

      def initialize(pool: Sidekiq.redis_pool)
        @pool = pool
        @type = :job # or :queue
        @period = :day
        # default to yesterday's data
        @date = (Date.today - 1)
        @hour = 0
        @queue = nil
        @klass = nil
      end

      # @returns [Hash] the resultset
      def fetch
        # coerce whatever the user gave us into a Date, could be
        # a Time or ActiveSupport::TimeWithZone, etc.
        @date = Date.new(@date.year, @date.month, @date.mday)

        resultset = {}
        resultset[:type] = @type
        resultset[:date] = @date
        resultset[:period] = @period
        resultset[:job_classes] = Set.new
        resultset[:queues] = Set.new

        datecode = @date.strftime("%Y%m%d")
        char = @type[0] # "j" or "q"

        results = @pool.with do |conn|
          conn.pipelined do |pipe|
            case @period
            when :month
              # we don't provide marks as this is expected to happen multiple
              # times per day which would fill any monthly graph with hundreds
              # of lines.
              resultset[:marks] = []
              resultset[:size] = 31
              monthcode = @date.strftime("%Y%m")
              31.times do |idx|
                pipe.hgetall "#{char}|#{monthcode}#{idx < 10 ? "0" : ""}#{idx}"
              end
            when :day
              resultset[:size] = 24
              24.times do |idx|
                pipe.hgetall "#{char}|#{datecode}|#{idx}"
              end
            when :hour
              resultset[:size] = 60
              resultset[:hour] = @hour
              60.times do |idx|
                pipe.hgetall "#{char}|#{datecode}|#{@hour}:#{idx}"
              end
            end
          end
        end

        # job classes always start with upper-case letter
        # queues should be lower-case
        results.each do |hash|
          resultset[:job_classes].merge(hash.keys.select { |k| UPPER.include?(k[0].ord) }.map { |k| k.split("|")[0] })
          resultset[:queues].merge(hash.keys.select { |k| !UPPER.include?(k[0].ord) }.map { |k| k.split("|")[0] })
        end

        if @type == :job && @klass
          results.each { |hash| hash.delete_if { |k, v| !k.start_with?("#{@klass}|") } }
        elsif @type == :queue && @queue
          results.each { |hash| hash.delete_if { |k, v| !k.start_with?("#{@queue}|") } }
        end

        if @period == :day || @period == :hour
          resultset[:marks] = @pool.with { |c| c.hgetall("#{datecode}-marks") }
        end

        resultset[:data] = results
        resultset
      end

      # ASCII uppercase range
      UPPER = 65..90
    end
  end
end