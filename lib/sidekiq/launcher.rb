# frozen_string_literal: true

require "sidekiq/manager"
require "sidekiq/fetch"
require "sidekiq/scheduled"
require "sidekiq/ring_buffer"

module Sidekiq
  # The Launcher starts the Manager and Poller threads and provides the process heartbeat.
  class Launcher
    include Sidekiq::Component

    PROCTITLES = [
      proc { "sidekiq" },
      proc { Sidekiq::VERSION },
      proc { |me, data| data["tag"] },
      proc { |me, data| "[#{Processor::WORK_STATE.size} of #{data["concurrency"]} busy]" },
      proc { |me, data| "stopping" if me.stopping? }
    ]

    attr_accessor :manager, :poller, :fetcher

    def initialize(options)
      @config = options
      options[:fetch] ||= BasicFetch.new(options)
      @manager = Sidekiq::Manager.new(options)
      @poller = Sidekiq::Scheduled::Poller.new(options)
      @done = false
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

    # Shuts down this Sidekiq instance. Waits up to the deadline for all jobs to complete.
    def stop
      deadline = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) + @config[:timeout]

      @done = true
      @manager.quiet
      @poller.terminate

      @manager.stop(deadline)

      # Requeue everything in case there was a thread which fetched a job while the process was stopped.
      # This call is a no-op in Sidekiq but necessary for Sidekiq Pro.
      strategy = @config[:fetch]
      strategy.bulk_requeue([], @config)

      clear_heartbeat
    end

    def stopping?
      @done
    end

    private unless $TESTING

    BEAT_PAUSE = 10

    def start_heartbeat
      loop do
        heartbeat
        sleep BEAT_PAUSE
      end
      logger.info("Heartbeat stopping...")
    end

    def clear_heartbeat
      Sidekiq::Metrics::PROCESSED.flush

      # Remove record from Redis since we are shutting down.
      # Note we don't stop the heartbeat thread; if the process
      # doesn't actually exit, it'll reappear in the Web UI.
      redis do |conn|
        conn.pipelined do |pipeline|
          pipeline.srem("processes", identity)
          pipeline.unlink("#{identity}:work")
        end
      end
    rescue
      # best effort, ignore network errors
    end

    def heartbeat
      $0 = PROCTITLES.map { |proc| proc.call(self, to_data) }.compact.join(" ")

      ❤
    end

    def ❤
      key = identity

      begin
        curstate = Processor::WORK_STATE.dup
        redis do |conn|
          # work is the current set of executing jobs
          work_key = "#{key}:work"
          conn.pipelined do |transaction|
            transaction.unlink(work_key)
            curstate.each_pair do |tid, hash|
              transaction.hset(work_key, tid, Sidekiq.dump_json(hash))
            end
            transaction.expire(work_key, 60)
          end
        end

        rtt = check_rtt

        kb = memory_usage($$)

        _, exists, _, _, msg = redis do |conn|
          conn.multi do |transaction|
            transaction.sadd("processes", key)
            transaction.exists?(key)
            transaction.hmset(key, "info", to_json,
              "busy", curstate.size,
              "beat", Time.now.to_f,
              "rtt_us", rtt,
              "quiet", @done.to_s,
              "rss", kb)
            transaction.expire(key, 60)
            transaction.rpop("#{key}-signals")
          end
        end

        fire_event(:beat, oneshot: false)
        # first heartbeat or recovering from an outage and need to reestablish our heartbeat
        fire_event(:heartbeat) unless exists

        ::Process.kill(msg, $$) if msg
      rescue => e
        # ignore all redis/network issues
        logger.error("heartbeat: #{e}")
      end
    end

    # We run the heartbeat every five seconds.
    # Capture five samples of RTT, log a warning if each sample
    # is above our warning threshold.
    RTT_READINGS = RingBuffer.new(5)
    RTT_WARNING_LEVEL = 50_000

    def check_rtt
      a = b = 0
      redis do |x|
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
        logger.warn <<~EOM
          Your Redis network connection is performing extremely poorly.
          Last RTT readings were #{RTT_READINGS.buffer.inspect}, ideally these should be < 1000.
          Ensure Redis is running in the same AZ or datacenter as Sidekiq.
          If these values are close to 100,000, that means your Sidekiq process may be
          CPU-saturated; reduce your concurrency and/or see https://github.com/mperham/sidekiq/discussions/5039
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
        "tag" => @config[:tag] || "",
        "concurrency" => @config[:concurrency],
        "queues" => @config[:queues].uniq,
        "labels" => @config[:labels],
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
