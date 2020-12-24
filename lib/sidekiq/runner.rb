# frozen_string_literal: true

require "sidekiq/loggable"
require "sidekiq/manager"
require "sidekiq/fetch"
require "sidekiq/scheduled"

module Sidekiq
  class Runner
    include Util

    STATS_TTL = 5 * 365 * 24 * 60 * 60 # 5 years

    attr_reader :manager, :poller, :fetcher

    def initialize(cfg)
      @config = cfg
      @done = false
    end

    # Run Sidekiq. If `install_signals` is true, this method does not return.
    # If false, you are responsible for hooking into the process signals and
    # calling `stop` to shut down the Sidekiq processor threads.
    def run(install_signals: true)
      @manager = Sidekiq::Manager.new(@config)
      @poller = Sidekiq::Scheduled::Poller.new(@config)
      @fetcher ||= BasicFetch.new(@config)
      @thread = safe_thread("heartbeat", &method(:start_heartbeat))
      @poller.start
      @manager.start

      if install_signals
        self_read = hook
        begin
          loop do
            readable_io = IO.select([self_read])
            signal = readable_io.first[0].gets.strip
            handle_signal(signal)
          end
        rescue Interrupt
          logger.info "Shutting down"
          stop
          logger.info "Bye!"
          # Explicitly exit so busy Processor threads won't block process shutdown.
          #
          # NB: slow at_exit handlers will prevent a timely exit if they take
          # a while to run. If Sidekiq is getting here but the process isn't exiting,
          # use the TTIN signal to determine where things are stuck.
          exit(0)
        end
      end
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
      deadline = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) + @config.shutdown_timeout

      @done = true
      @manager.quiet
      @poller.terminate

      @manager.stop(deadline, @fetcher)

      # Requeue everything in case there was a worker who grabbed work while stopped
      # This call is a no-op in Sidekiq but necessary for Sidekiq Pro.
      @fetcher.bulk_requeue({})

      clear_heartbeat
    end

    def stopping?
      @done
    end

    private unless $TESTING

    def hook
      self_read, self_write = IO.pipe
      sigs = %w[INT TERM TTIN TSTP]
      # USR1 and USR2 don't work on the JVM
      sigs << "USR2" if Sidekiq.pro? && !defined?(::JRUBY_VERSION)
      sigs.each do |sig|
        trap sig do
          self_write.puts(sig)
        end
      rescue ArgumentError
        puts "Signal #{sig} not supported"
      end
      self_read
    end

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
          "tag" => @config.tag,
          "concurrency" => @config.concurrency,
          "queues" => @config.queues.uniq,
          "labels" => @config.labels.to_a,
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
