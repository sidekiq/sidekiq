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
      @condvar = ::ConditionVariable.new
      @manager = Sidekiq::Manager.new(@condvar, options)
      @poller = Sidekiq::Scheduled::Poller.new
      @fetcher = Sidekiq::Fetcher.new(@manager, options)
      @manager.fetcher = @fetcher
      @done = false
      @options = options
    end

    def run
      @thread = safe_thread("heartbeat", &method(:start_heartbeat))
      @fetcher.start
      @poller.start
      @manager.start
    end

    # Stops this instance from processing any more jobs,
    #
    def quiet
      @manager.quiet
      @fetcher.terminate
      @poller.terminate
    end

    # Shuts down the process.  This method does not
    # return until all work is complete and cleaned up.
    # It can take up to the timeout to complete.
    def stop
      deadline = Time.now + @options[:timeout]

      @manager.quiet
      @fetcher.terminate
      @poller.terminate

      @manager.stop(deadline)

      # Requeue everything in case there was a worker who grabbed work while stopped
      # This call is a no-op in Sidekiq but necessary for Sidekiq Pro.
      Sidekiq::Fetcher.strategy.bulk_requeue([], @options)

      stop_heartbeat
    end

    private unless $TESTING

    JVM_RESERVED_SIGNALS = ['USR1', 'USR2'] # Don't Process#kill if we get these signals via the API

    PROCTITLES = [
      proc { 'sidekiq'.freeze },
      proc { Sidekiq::VERSION },
      proc { |me, data| data['tag'] },
      proc { |me, data| "[#{me.manager.in_progress.size} of #{data['concurrency']} busy]" },
      proc { |me, data| "stopping" if me.manager.stopped? },
    ]

    def heartbeat(key, data, json)
      results = PROCTITLES.map {|x| x.(self, data) }
      results.compact!
      $0 = results.join(' ')

      ❤(key, json)
    end

    def ❤(key, json)
      begin
        _, _, _, msg = Sidekiq.redis do |conn|
          conn.pipelined do
            conn.sadd('processes', key)
            conn.hmset(key, 'info', json, 'busy', manager.in_progress.size, 'beat', Time.now.to_f)
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
      end
    end

    def start_heartbeat
      key = identity
      data = {
        'hostname' => hostname,
        'started_at' => Time.now.to_f,
        'pid' => $$,
        'tag' => @options[:tag] || '',
        'concurrency' => @options[:concurrency],
        'queues' => @options[:queues].uniq,
        'labels' => @options[:labels],
        'identity' => identity,
      }
      # this data doesn't change so dump it to a string
      # now so we don't need to dump it every heartbeat.
      json = Sidekiq.dump_json(data)

      while !@done
        heartbeat(key, data, json)
        sleep 5
      end
    end

    def stop_heartbeat
      @done = true
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
