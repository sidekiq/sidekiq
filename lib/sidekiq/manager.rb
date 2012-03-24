require 'celluloid'
require 'redis'
require 'multi_json'

require 'sidekiq/util'
require 'sidekiq/processor'
require 'sidekiq/fetch'
require 'connection_pool/version'

module Sidekiq

  ##
  # The main router in the system.  This
  # manages the processor state and accepts messages
  # from Redis to be dispatched to an idle processor.
  #
  class Manager
    include Util
    include Celluloid

    trap_exit :processor_died

    def initialize(options={})
      logger.info "Booting sidekiq #{Sidekiq::VERSION} with Redis at #{redis {|x| x.client.location}}"
      logger.info "Running in #{RUBY_DESCRIPTION}"
      logger.debug { options.inspect }
      @count = options[:concurrency] || 25
      @done_callback = nil

      @done = false
      @busy = []
      @ready = @count.times.map { Processor.new_link(current_actor) }
      @fetcher = Sidekiq::Fetcher.new(current_actor, options[:queues])
    end

    def stop(options={})
      shutdown = options[:shutdown]
      timeout = options[:timeout]

      @done = true

      @fetcher.terminate if @fetcher.alive?
      @ready.each { |x| x.terminate if x.alive? }
      @ready.clear

      redis do |conn|
        workers = conn.smembers('workers')
        workers.each do |name|
          conn.srem('workers', name) if name =~ /:#{process_id}-/
        end
      end

      if shutdown
        if @busy.empty?
          # after(0) needed to avoid deadlock in Celluoid after USR1 + TERM
          return after(0) { signal(:shutdown) }
        else
          logger.info { "Pausing #{timeout} seconds to allow workers to finish..." }
        end

        after(timeout) do
          @busy.each { |x| x.terminate if x.alive? }
          signal(:shutdown)
        end
      end
    end

    def start
      dispatch
    end

    def when_done(&blk)
      @done_callback = blk
    end

    def processor_done(processor)
      watchdog('Manager#processor_done died') do
        @done_callback.call(processor) if @done_callback
        @busy.delete(processor)
        if stopped?
          processor.terminate if processor.alive?
          signal(:shutdown) if @busy.empty?
        else
          @ready << processor if processor.alive?
        end
        dispatch
      end
    end

    def processor_died(processor, reason)
      watchdog("Manager#processor_died died") do
        @busy.delete(processor)

        unless stopped?
          @ready << Processor.new_link(current_actor)
          dispatch
        else
          signal(:shutdown) if @busy.empty?
        end
      end
    end

    def assign(msg, queue)
      watchdog("Manager#assign died") do
        processor = @ready.pop
        @busy << processor
        processor.process!(MultiJson.decode(msg), queue)
        dispatch
      end
    end

    private

    def dispatch
      return if stopped?
      # This is a safety check to ensure we haven't leaked
      # processors somehow.
      raise "BUG: No processors, cannot continue!" if @ready.empty? && @busy.empty?
      return if @ready.empty?

      @fetcher.fetch!
    end

    def stopped?
      @done
    end
  end
end
