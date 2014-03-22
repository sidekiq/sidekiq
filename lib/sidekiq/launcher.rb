require 'sidekiq/actor'
require 'sidekiq/manager'
require 'sidekiq/fetch'
require 'sidekiq/scheduled'

module Sidekiq
  # The Launcher is a very simple Actor whose job is to
  # start, monitor and stop the core Actors in Sidekiq.
  # If any of these actors die, the Sidekiq process exits
  # immediately.
  class Launcher
    include Actor
    include Util

    trap_exit :actor_died

    attr_reader :manager, :poller, :fetcher

    def initialize(options)
      @manager = Sidekiq::Manager.new_link options
      @poller = Sidekiq::Scheduled::Poller.new_link
      @fetcher = Sidekiq::Fetcher.new_link @manager, options
      @manager.fetcher = @fetcher
      @done = false
      @options = options
    end

    def actor_died(actor, reason)
      return if @done
      Sidekiq.logger.warn("Sidekiq died due to the following error, cannot recover, process exiting")
      handle_exception(reason)
      exit(1)
    end

    def run
      watchdog('Launcher#run') do
        manager.async.start
        poller.async.poll(true)

        start_heartbeat
      end
    end

    def stop
      watchdog('Launcher#stop') do
        @done = true
        Sidekiq::Fetcher.done!
        fetcher.terminate if fetcher.alive?
        poller.terminate if poller.alive?

        manager.async.stop(:shutdown => true, :timeout => @options[:timeout])
        manager.wait(:shutdown)

        # Requeue everything in case there was a worker who grabbed work while stopped
        Sidekiq::Fetcher.strategy.bulk_requeue([], @options)

        stop_heartbeat
      end
    end

    private

    def start_heartbeat
      key = identity
      data = {
        'hostname' => hostname,
        'started_at' => Time.now.to_f,
        'pid' => $$,
        'tag' => @options[:tag] || '',
        'concurrency' => @options[:concurrency],
        'queues' => @options[:queues].uniq,
      }
      Sidekiq.redis do |conn|
        conn.multi do
          conn.sadd('processes', key)
          conn.hset(key, 'info', Sidekiq.dump_json(data))
          conn.expire(key, 60)
        end
      end
      manager.heartbeat(key, data)
    end

    def stop_heartbeat
      Sidekiq.redis do |conn|
        conn.srem('processes', identity)
      end
    end
  end
end
