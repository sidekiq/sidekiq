require 'sidekiq/util'
require 'sidekiq/manager'
require 'sidekiq/scheduled'

module Sidekiq
  class Launcher
    attr_reader :manager, :poller, :options
    def initialize(options)
      @options = options
      @manager = Sidekiq::Manager.new(options)
      @poller  = Sidekiq::Scheduled::Poller.new
    end

    def run
      manager.async.start
      poller.async.poll(true)
    end

    def stop
      poller.async.terminate if poller.alive?
      manager.async.stop(:shutdown => true, :timeout => options[:timeout])
      manager.wait(:shutdown)
    end

    def procline(tag)
      $0 = manager.procline(tag)
      manager.after(5) { procline(tag) }
    end
  end
end
