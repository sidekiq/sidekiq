# frozen_string_literal: true

require "sidekiq/manager"
require "sidekiq/fetch"
require "sidekiq/scheduled"

module Sidekiq
  class Runner
    include Util

    STATS_TTL = 5 * 365 * 24 * 60 * 60 # 5 years

    attr_accessor :manager, :poller, :fetcher

    def initialize
      @concurrency = 10
      @shutdown_timeout = 25
      @environment = "development"
      @middleware = Sidekiq::Middleware::Chain.new
      @event_hooks = {
        startup: [],
        quiet: [],
        shutdown: [],
        heartbeat: []
      }
      @death_handlers = []
      @error_handlers = [->(ex, ctx) {
        @logger.warn(Sidekiq.dump_json(ctx)) unless ctx.empty?
        @logger.warn("#{ex.class.name}: #{ex.message}")
        @logger.warn(ex.backtrace.join("\n")) unless ex.backtrace.nil?
      }]

      @done = false
    end

    def run
      @manager = Sidekiq::Manager.new
      @poller = Sidekiq::Scheduled::Poller.new
      @fetcher ||= BasicFetch.new
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
      @fetcher.bulk_requeue

      clear_heartbeat
    end

    def stopping?
      @done
    end

    private unless $TESTING

    def start_heartbeat
      loop do
        ❤
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

        fails = procd = 0
        kb = memory_usage(::Process.pid)

        _, exists, _, _, msg = Sidekiq.redis { |conn|
          conn.multi {
            conn.sadd("processes", key)
            conn.exists?(key)
            conn.hmset(key, "info", to_json,
              "busy", curstate.size,
              "beat", Time.now.to_f,
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
      @data ||= begin
        {
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
    end

    def to_json
      @json ||= begin
        # this data changes infrequently so dump it to a string
        # now so we don't need to dump it every heartbeat.
        Sidekiq.dump_json(to_data)
      end
    end
  end
end
