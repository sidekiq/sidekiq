require "time"
require "sidekiq"

# This file contains the components which track execution metrics within Sidekiq.
module Sidekiq
  module Metrics
    # Impleements space-efficient but statistically useful histogram storage.
    # A precise time histogram stores every time. Instead we break times into a set of
    # known buckets and increment counts of the associated time bucket. Even if we call
    # the histogram a million times, we'll still only store 26 buckets.
    # NB: needs to be thread-safe or resiliant to races.
    #
    # To store this data, we use Redis' BITFIELD command to store unsigned 16-bit counters
    # per minute. It's unlikely that most people will be executing more than 1000 job/sec
    # for a full minute of a specific type.
    class Histogram
      include Enumerable

      BUCKET_INTERVALS = [
        20, 30, 45, 65, 100,
        150, 225, 335, 500, 750,
        1100, 1700, 2500, 3800, 5750,
        8500, 13000, 20000, 30000, 45000,
        65000, 100000, 150000, 225000, 335000,
        Float::INFINITY # the "maybe your job is too long" bucket
      ]

      FETCH = "GET u16 #0 GET u16 #1 GET u16 #2 GET u16 #3 \
        GET u16 #4 GET u16 #5 GET u16 #6 GET u16 #7 \
        GET u16 #8 GET u16 #9 GET u16 #10 GET u16 #11 \
        GET u16 #12 GET u16 #13 GET u16 #14 GET u16 #15 \
        GET u16 #16 GET u16 #17 GET u16 #18 GET u16 #19 \
        GET u16 #20 GET u16 #21 GET u16 #22 GET u16 #23 \
        GET u16 #24 GET u16 #25".split

      def each(&block)
        buckets.each(&block)
      end

      attr_reader :buckets
      def initialize(klass)
        @klass = klass
        @buckets = Array.new(BUCKET_INTERVALS.size, 0)
      end

      def record_time(ms)
        index_to_use = BUCKET_INTERVALS.each_index do |idx|
          break idx if ms < BUCKET_INTERVALS[idx]
        end

        @buckets[index_to_use] += 1
      end

      def fetch(conn, now = Time.now)
        window = now.utc.strftime("%d-%H:%-M")
        key = "#{@klass}-#{window}"
        conn.bitfield(key, *FETCH)
      end

      def persist(conn, now = Time.now)
        buckets, @buckets = @buckets, []
        window = now.utc.strftime("%d-%H:%-M")
        key = "#{@klass}-#{window}"
        cmd = ["#{@klass}-#{window}", "OVERFLOW", "SAT"]
        buckets.each_with_index do |value, idx|
          next if value == 0
          cmd << "INCRBY" << "u16" << "##{idx}" << value.to_s
        end
        conn.bitfield(*cmd) if cmd.size > 1
        conn.expire(key, 86400)
        key
      end
    end

    class ExecutionTracker
      include Sidekiq::Component

      def initialize(config)
        @config = config
        @jobs = Hash.new(0)
        @totals = Hash.new(0)
        @grams = Hash.new { |key| Histogram.new(key) }
        @lock = Mutex.new
      end

      def track(queue, klass)
        start = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC, :millisecond)
        time_ms = 0
        begin
          begin
            yield
          ensure
            finish = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC, :millisecond)
            time_ms = finish - start
          end
          # We don't track time for failed jobs as they can have very unpredictable
          # execution times. more important to know average time for successful jobs so we
          # can better recognize when a perf regression is introduced.
          @lock.synchronize {
            @grams[klass].record_time(time_ms)
            @jobs["#{klass}|ms"] += time_ms
            @totals["ms"] += time_ms
          }
        rescue Exception
          @lock.synchronize {
            @jobs["#{klass}|f"] += 1
            @totals["f"] += 1
          }
          raise
        ensure
          @lock.synchronize {
            @jobs["#{klass}|p"] += 1
            @totals["p"] += 1
          }
        end
      end

      STATS_TTL = 5 * 365 * 24 * 60 * 60 # 5 years

      LONG_TERM = 90 * 24 * 60 * 60
      MID_TERM = 7 * 24 * 60 * 60
      SHORT_TERM = 8 * 60 * 60

      def flush(time = Time.now)
        totals, jobs, grams = reset
        procd = totals["p"]
        fails = totals["f"]
        return if procd == 0 && fails == 0

        now = time.utc
        nowdate = now.strftime("%Y%m%d")
        nowhour = now.strftime("%Y%m%d|%-H")
        nowmin = now.strftime("%Y%m%d|%-H:%-M")
        count = 0

        redis do |conn|
          conn.pipelined do |pipeline|
            pipeline.incrby("stat:processed", procd)
            pipeline.incrby("stat:processed:#{nowdate}", procd)
            pipeline.expire("stat:processed:#{nowdate}", STATS_TTL)

            pipeline.incrby("stat:failed", fails)
            pipeline.incrby("stat:failed:#{nowdate}", fails)
            pipeline.expire("stat:failed:#{nowdate}", STATS_TTL)
          end

          conn.pipelined do |pipe|
            grams.each do |gram|
              gram.persist(conn)
            end
          end

          [
            ["j", jobs, nowdate, LONG_TERM],
            ["j", jobs, nowhour, MID_TERM],
            ["j", jobs, nowmin, SHORT_TERM]
          ].each do |prefix, data, bucket, ttl|
            # Quietly seed the new 7.0 stats format so migration is painless.
            conn.pipelined do |xa|
              stats = "#{prefix}|#{bucket}"
              # logger.debug "Flushing metrics #{stats}"
              data.each_pair do |key, value|
                xa.hincrby stats, key, value
                count += 1
              end
              xa.expire(stats, ttl)
            end
          end
          logger.info "Flushed #{count} elements"
          count
        end
      end

      private

      def reset
        @lock.synchronize {
          array = [@totals, @jobs, @grams]
          @totals = Hash.new(0)
          @jobs = Hash.new(0)
          @grams = Hash.new { |key| Histogram.new(key) }
          array
        }
      end
    end

    class Middleware
      include Sidekiq::ServerMiddleware

      def initialize(options)
        @exec = options
      end

      def call(_instance, hash, queue, &block)
        @exec.track(queue, hash["wrapped"] || hash["class"], &block)
      end
    end
  end
end

Sidekiq.configure_server do |config|
  exec = Sidekiq::Metrics::ExecutionTracker.new(config)
  config.server_middleware do |chain|
    chain.add Sidekiq::Metrics::Middleware, exec
  end
  config.on(:beat) do
    exec.flush
  end
end
