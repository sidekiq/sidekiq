# frozen_string_literal: true

require "sidekiq/manager"
require "sidekiq/fetch"
require "sidekiq/scheduled"

module Sidekiq
  # The Launcher starts the Manager and Poller threads and provides the process heartbeat.
  class Launcher
    include Util

    STATS_TTL = 5 * 365 * 24 * 60 * 60 # 5 years

    PROCTITLES = [
      proc { "sidekiq" },
      proc { Sidekiq::VERSION },
      proc { |me, data| data["tag"] },
      proc { |me, data| "[#{Processor::WORKER_STATE.size} of #{data["concurrency"]} busy]" },
      proc { |me, data| "stopping" if me.stopping? }
    ]

    attr_accessor :manager, :poller, :fetcher

    def initialize(options)
      options[:fetch] ||= BasicFetch.new(options)
      @manager = Sidekiq::Manager.new(options)
      @poller = Sidekiq::Scheduled::Poller.new
      @done = false
      @options = options
    end

    def run
      @thread = safe_thread("heartbeat", &method(:start_heartbeat))
      @poller.start
      @manager.start
    end

    # Stops this instance from processing any more jobs,
    #
    def quiet
      @done = true
      @manager.quiet
      @poller.terminate
    end

    # Shuts down the process.  This method does not
    # return until all work is complete and cleaned up.
    # It can take up to the timeout to complete.
    def stop
      deadline = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) + @options[:timeout]

      @done = true
      @manager.quiet
      @poller.terminate

      @manager.stop(deadline)

      # Requeue everything in case there was a worker who grabbed work while stopped
      # This call is a no-op in Sidekiq but necessary for Sidekiq Pro.
      strategy = @options[:fetch]
      strategy.bulk_requeue([], @options)

      clear_heartbeat
    end

    def stopping?
      @done
    end

    private unless $TESTING

    def start_heartbeat
      loop do
        heartbeat
        sleep 5
      end
      Sidekiq.logger.info("Heartbeat stopping...")
    end

    def clear_heartbeat
      # Remove record from Redis since we are shutting down.
      # Note we don't stop the heartbeat thread; if the process
      # doesn't actually exit, it'll reappear in the Web UI.
      Sidekiq.redis do |conn|
        conn.pipelined do
          conn.srem("processes", identity)
          conn.unlink("#{identity}:workers")
        end
      end
    rescue
      # best effort, ignore network errors
    end

    def heartbeat
      $0 = PROCTITLES.map { |proc| proc.call(self, to_data) }.compact.join(" ")

      ❤
    end

    def self.flush_stats
      fails = Processor::FAILURE.reset
      procd = Processor::PROCESSED.reset
      return if fails + procd == 0

      nowdate = Time.now.utc.strftime("%Y-%m-%d")
      begin
        Sidekiq.redis do |conn|
          conn.pipelined do
            conn.incrby("stat:processed", procd)
            conn.incrby("stat:processed:#{nowdate}", procd)
            conn.expire("stat:processed:#{nowdate}", STATS_TTL)

            conn.incrby("stat:failed", fails)
            conn.incrby("stat:failed:#{nowdate}", fails)
            conn.expire("stat:failed:#{nowdate}", STATS_TTL)
          end
        end
      rescue => ex
        # we're exiting the process, things might be shut down so don't
        # try to handle the exception
        Sidekiq.logger.warn("Unable to flush stats: #{ex}")
      end
    end
    at_exit(&method(:flush_stats))

    def ❤
      key = identity
      fails = procd = 0

      begin
        fails = Processor::FAILURE.reset
        procd = Processor::PROCESSED.reset
        curstate = Processor::WORKER_STATE.dup

        workers_key = "#{key}:workers"
        nowdate = Time.now.utc.strftime("%Y-%m-%d")

        Sidekiq.redis do |conn|
          conn.multi do
            conn.incrby("stat:processed", procd)
            conn.incrby("stat:processed:#{nowdate}", procd)
            conn.expire("stat:processed:#{nowdate}", STATS_TTL)

            conn.incrby("stat:failed", fails)
            conn.incrby("stat:failed:#{nowdate}", fails)
            conn.expire("stat:failed:#{nowdate}", STATS_TTL)

            conn.unlink(workers_key)
            curstate.each_pair do |tid, hash|
              conn.hset(workers_key, tid, Sidekiq.dump_json(hash))
            end
            conn.expire(workers_key, 60)
          end
        end

        rtt = check_rtt

        fails = procd = 0
        kb = memory_usage(::Process.pid)

        _, exists, _, _, msg = Sidekiq.redis { |conn|
          conn.multi {
            conn.sadd("processes", key)
            conn.exists?(key)
            conn.hmset(key, "info", to_json,
              "busy", curstate.size,
              "beat", Time.now.to_f,
              "rtt_us", rtt,
              "quiet", @done,
              "rss", kb)
            conn.expire(key, 60)
            conn.rpop("#{key}-signals")
          }
        }

        # first heartbeat or recovering from an outage and need to reestablish our heartbeat
        fire_event(:heartbeat) unless exists

        return unless msg

        ::Process.kill(msg, ::Process.pid)
      rescue => e
        # ignore all redis/network issues
        logger.error("heartbeat: #{e}")
        # don't lose the counts if there was a network issue
        Processor::PROCESSED.incr(procd)
        Processor::FAILURE.incr(fails)
      end
    end

    # We run the heartbeat every five seconds.
    # Capture five samples of RTT, log a warning if each sample
    # is above our warning threshold.
    RTT_READINGS = RingBuffer.new(5)
    RTT_WARNING_LEVEL = 50_000

    def check_rtt
      a = b = 0
      Sidekiq.redis do |x|
        a = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC, :microsecond)
        x.ping
        b = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC, :microsecond)
      end
      rtt = b - a
      RTT_READINGS << rtt
      # Ideal RTT for Redis is < 1000µs
      # Workable is < 10,000µs
      # Log a warning if it's a disaster.
      if RTT_READINGS.all? { |x| x > RTT_WARNING_LEVEL }
        Sidekiq.logger.warn <<~EOM
          Your Redis network connection is performing extremely poorly.
          Last RTT readings were #{RTT_READINGS.buffer.inspect}, ideally these should be < 1000.
          Ensure Redis is running in the same AZ or datacenter as Sidekiq.
        EOM
        RTT_READINGS.reset
      end
      rtt
    end

    MEMORY_GRABBER = case RUBY_PLATFORM
    when /linux/
      ->(pid) {
        IO.readlines("/proc/#{$$}/status").each do |line|
          next unless line.start_with?("VmRSS:")
          break line.split[1].to_i
        end
      }
    when /darwin|bsd/
      ->(pid) {
        `ps -o pid,rss -p #{pid}`.lines.last.split.last.to_i
      }
    else
      ->(pid) { 0 }
    end

    def memory_usage(pid)
      MEMORY_GRABBER.call(pid)
    end

    def to_data
      @data ||= {
        "hostname" => hostname,
        "started_at" => Time.now.to_f,
        "pid" => ::Process.pid,
        "tag" => @options[:tag] || "",
        "concurrency" => @options[:concurrency],
        "queues" => @options[:queues].uniq,
        "labels" => @options[:labels],
        "identity" => identity
      }
    end

    def to_json
      # this data changes infrequently so dump it to a string
      # now so we don't need to dump it every heartbeat.
      @json ||= Sidekiq.dump_json(to_data)
    end
  end
end
