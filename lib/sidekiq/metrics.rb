require "time"

module Sidekiq
  module Metrics
    def self.track(config)
      exec = Sidekiq::Metrics::ExecutionTracker.new(config)
      config.server_middleware do |chain|
        chain.add Sidekiq::Metrics::Middleware, exec
      end
      config.on(:beat) do
        exec.flush
      end
    end

    class ExecutionTracker
      include Sidekiq::Component

      def initialize(config)
        @config = config
        @queues = Hash.new(0)
        @jobs = Hash.new(0)
        @totals = Hash.new(0)
        @lock = Mutex.new
      end

      # We track success/failure and time per class and per queue.
      # "q:default|ms" => 1755 means 1755ms executing jobs from the default queue
      # "Foo::SomeJob|f" => 5 means Foo::SomeJob failed 5 times
      #
      # All of these values are rolled up into one "exec" Hash per day in Redis:
      # "exec:2022-07-06", etc by the heartbeat.
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
            @queues["#{queue}|ms"] += time_ms
            @jobs["#{klass}|ms"] += time_ms
            @totals["ms"] += time_ms
          }
        rescue Exception
          @lock.synchronize {
            @queues["#{queue}|f"] += 1
            @jobs["#{klass}|f"] += 1
            @totals["f"] += 1
          }
          raise
        ensure
          @lock.synchronize {
            @queues["#{queue}|p"] += 1
            @jobs["#{klass}|p"] += 1
            @totals["p"] += 1
          }
        end
      end

      STATS_TTL = 5 * 365 * 24 * 60 * 60 # 5 years

      def flush(time = Time.now)
        totals, queues, jobs = reset
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

          [
            ["j", jobs, nowdate, 90 * 24 * 60 * 60],
            ["q", queues, nowdate, 90 * 24 * 60 * 60],
            ["j", jobs, nowhour, 7 * 24 * 60 * 60],
            ["q", queues, nowhour, 7 * 24 * 60 * 60],
            ["j", jobs, nowmin, 2 * 60 * 60]
            # don't want queue data per min, not really that useful IMO
          ].each do |prefix, data, bucket, ttl|
            # Quietly seed the new 7.0 stats format so migration is painless.
            conn.pipelined do |xa|
              stats = "#{prefix}|#{bucket}"
              logger.info "Flushing metrics #{stats}"
              data.each_pair do |key, value|
                xa.hincrby stats, key, value
                count += 1
              end
              xa.expire(stats, ttl)
            end
          end
          count
        end
      end

      private

      def reset
        @lock.synchronize {
          array = [@totals, @queues, @jobs]
          @totals = Hash.new(0)
          @queues = Hash.new(0)
          @jobs = Hash.new(0)
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
