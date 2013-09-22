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

    trap_exit :actor_died

    attr_reader :manager, :poller, :fetcher

    def initialize(options)
      @manager = Sidekiq::Manager.new_link options
      @poller = Sidekiq::Scheduled::Poller.new_link
      @fetcher = Sidekiq::Fetcher.new_link @manager, options
      @done = false
      @options = options
    end

    def actor_died(actor, reason)
      return if @done
      Sidekiq.logger.warn("Sidekiq died: #{reason}")
      Sidekiq.logger.warn("Cannot recover, process exiting")
      exit(1)
    end

    def run
      manager.async.start(fetcher)
      poller.async.poll(true)
    end

    def stop
      @done = true
      Sidekiq::Fetcher.done!
      fetcher.async.terminate if fetcher.alive?
      poller.async.terminate if poller.alive?

      manager.async.stop(:shutdown => true, :timeout => @options[:timeout])
      manager.wait(:shutdown)
    end

    def procline(tag)
      $0 = manager.procline(tag)
      manager.after(5) { procline(tag) }
    end
  end
end
