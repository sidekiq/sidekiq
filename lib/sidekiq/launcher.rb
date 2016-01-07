# encoding: utf-8
require 'sidekiq/manager'
require 'sidekiq/fetch'
require 'sidekiq/scheduled'

module Sidekiq
  # The Launcher is a very simple Actor whose job is to
  # start, monitor and stop the core Actors in Sidekiq.
  # If any of these actors die, the Sidekiq process exits
  # immediately.
  class Launcher
    include Util

    attr_accessor :manager, :poller, :fetcher

    def initialize(options)
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
      deadline = Time.now + @options[:timeout]

      @done = true
      @manager.quiet
      @poller.terminate

      @manager.stop(deadline)

      # Requeue everything in case there was a worker who grabbed work while stopped
      # This call is a no-op in Sidekiq but necessary for Sidekiq Pro.
      strategy = (@options[:fetch] || Sidekiq::BasicFetch)
      strategy.bulk_requeue([], @options)

      clear_heartbeat
    end

    def stopping?
      @done
    end

    private unless $TESTING

    JVM_RESERVED_SIGNALS = ['USR1', 'USR2'] # Don't Process#kill if we get these signals via the API

    def heartbeat(k, data, json)
      results = Sidekiq::CLI::PROCTITLES.map {|x| x.(self, data) }
      results.compact!
      $0 = results.join(' ')

      ❤(k, json)
    end

    def ❤(key, json)
      fails = procd = 0
      begin
        Processor::FAILURE.update {|curr| fails = curr; 0 }
        Processor::PROCESSED.update {|curr| procd = curr; 0 }

        workers_key = "#{key}:workers".freeze
        nowdate = Time.now.utc.strftime("%Y-%m-%d".freeze)
        Sidekiq.redis do |conn|
          conn.pipelined do
            conn.incrby("stat:processed".freeze, procd)
            conn.incrby("stat:processed:#{nowdate}", procd)
            conn.incrby("stat:failed".freeze, fails)
            conn.incrby("stat:failed:#{nowdate}", fails)
            conn.del(workers_key)
            Processor::WORKER_STATE.each_pair do |tid, hash|
              conn.hset(workers_key, tid, Sidekiq.dump_json(hash))
            end
          end
        end
        fails = procd = 0

        _, _, _, msg = Sidekiq.redis do |conn|
          conn.pipelined do
            conn.sadd('processes', key)
            conn.hmset(key, 'info', json, 'busy', Processor::WORKER_STATE.size, 'beat', Time.now.to_f, 'quiet', @done)
            conn.expire(key, 60)
            conn.rpop("#{key}-signals")
          end
        end

        return unless msg

        if JVM_RESERVED_SIGNALS.include?(msg)
          Sidekiq::CLI.instance.handle_signal(msg)
        else
          ::Process.kill(msg, $$)
        end
      rescue => e
        # ignore all redis/network issues
        logger.error("heartbeat: #{e.message}")
        # don't lose the counts if there was a network issue
        Processor::PROCESSED.increment(procd)
        Processor::FAILURE.increment(fails)
      end
    end

    def start_heartbeat
      k = identity
      data = {
        'hostname' => hostname,
        'started_at' => Time.now.to_f,
        'pid' => $$,
        'tag' => @options[:tag] || '',
        'concurrency' => @options[:concurrency],
        'queues' => @options[:queues].uniq,
        'labels' => @options[:labels],
        'identity' => k,
      }
      # this data doesn't change so dump it to a string
      # now so we don't need to dump it every heartbeat.
      json = Sidekiq.dump_json(data)

      while true
        heartbeat(k, data, json)
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
          conn.srem('processes', identity)
          conn.del("#{identity}:workers")
        end
      end
    rescue
      # best effort, ignore network errors
    end

  end
end
