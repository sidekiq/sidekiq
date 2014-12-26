# encoding: utf-8
require 'sidekiq/util'
require 'sidekiq/actor'
require 'sidekiq/processor'
require 'sidekiq/fetch'

module Sidekiq

  ##
  # The main router in the system.  This
  # manages the processor state and accepts messages
  # from Redis to be dispatched to an idle processor.
  #
  class Manager
    include Util
    include Actor
    trap_exit :processor_died

    attr_reader :ready
    attr_reader :busy
    attr_accessor :fetcher

    SPIN_TIME_FOR_GRACEFUL_SHUTDOWN = 1
    JVM_RESERVED_SIGNALS = ['USR1', 'USR2'] # Don't Process#kill if we get these signals via the API

    def initialize(condvar, options={})
      logger.debug { options.inspect }
      @options = options
      @count = options[:concurrency] || 25
      @done_callback = nil
      @finished = condvar

      @in_progress = {}
      @threads = {}
      @done = false
      @busy = []
      @ready = @count.times.map do
        p = Processor.new_link(current_actor)
        p.proxy_id = p.object_id
        p
      end
    end

    def stop(options={})
      watchdog('Manager#stop died') do
        should_shutdown = options[:shutdown]
        timeout = options[:timeout]

        @done = true

        logger.info { "Terminating #{@ready.size} quiet workers" }
        @ready.each { |x| x.terminate if x.alive? }
        @ready.clear

        return if clean_up_for_graceful_shutdown

        hard_shutdown_in timeout if should_shutdown
      end
    end

    def clean_up_for_graceful_shutdown
      if @busy.empty?
        shutdown
        return true
      end

      after(SPIN_TIME_FOR_GRACEFUL_SHUTDOWN) { clean_up_for_graceful_shutdown }
      false
    end

    def start
      @ready.each { dispatch }
    end

    def when_done(&blk)
      @done_callback = blk
    end

    def processor_done(processor)
      watchdog('Manager#processor_done died') do
        @done_callback.call(processor) if @done_callback
        @in_progress.delete(processor.object_id)
        @threads.delete(processor.object_id)
        @busy.delete(processor)
        if stopped?
          processor.terminate if processor.alive?
          shutdown if @busy.empty?
        else
          @ready << processor if processor.alive?
        end
        dispatch
      end
    end

    def processor_died(processor, reason)
      watchdog("Manager#processor_died died") do
        @in_progress.delete(processor.object_id)
        @threads.delete(processor.object_id)
        @busy.delete(processor)

        unless stopped?
          p = Processor.new_link(current_actor)
          p.proxy_id = p.object_id
          @ready << p
          dispatch
        else
          shutdown if @busy.empty?
        end
      end
    end

    def assign(work)
      watchdog("Manager#assign died") do
        if stopped?
          # Race condition between Manager#stop if Fetcher
          # is blocked on redis and gets a message after
          # all the ready Processors have been stopped.
          # Push the message back to redis.
          work.requeue
        else
          processor = @ready.pop
          @in_progress[processor.object_id] = work
          @busy << processor
          processor.async.process(work)
        end
      end
    end

    # A hack worthy of Rube Goldberg.  We need to be able
    # to hard stop a working thread.  But there's no way for us to
    # get handle to the underlying thread performing work for a processor
    # so we have it call us and tell us.
    def real_thread(proxy_id, thr)
      @threads[proxy_id] = thr
    end

    def heartbeat(key, data, json)
      proctitle = ['sidekiq', Sidekiq::VERSION]
      proctitle << data['tag'] unless data['tag'].empty?
      proctitle << "[#{@busy.size} of #{data['concurrency']} busy]"
      proctitle << 'stopping' if stopped?
      $0 = proctitle.join(' ')

      ❤(key, json)
      after(5) do
        heartbeat(key, data, json)
      end
    end

    private

    def ❤(key, json)
      begin
        _, _, _, msg = Sidekiq.redis do |conn|
          conn.multi do
            conn.sadd('processes', key)
            conn.hmset(key, 'info', json, 'busy', @busy.size, 'beat', Time.now.to_f)
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

    def hard_shutdown_in(delay)
      logger.info { "Pausing up to #{delay} seconds to allow workers to finish..." }

      after(delay) do
        watchdog("Manager#hard_shutdown_in died") do
          # We've reached the timeout and we still have busy workers.
          # They must die but their messages shall live on.
          logger.warn { "Terminating #{@busy.size} busy worker threads" }
          logger.warn { "Work still in progress #{@in_progress.values.inspect}" }

          requeue

          @busy.each do |processor|
            if processor.alive? && t = @threads.delete(processor.object_id)
              t.raise Shutdown
            end
          end

          @finished.signal
        end
      end
    end

    def dispatch
      return if stopped?
      # This is a safety check to ensure we haven't leaked
      # processors somehow.
      raise "BUG: No processors, cannot continue!" if @ready.empty? && @busy.empty?
      raise "No ready processor!?" if @ready.empty?

      @fetcher.async.fetch
    end

    def stopped?
      @done
    end

    def shutdown
      requeue
      @finished.signal
    end

    def requeue
      # Re-enqueue terminated jobs
      # NOTE: You may notice that we may push a job back to redis before
      # the worker thread is terminated. This is ok because Sidekiq's
      # contract says that jobs are run AT LEAST once. Process termination
      # is delayed until we're certain the jobs are back in Redis because
      # it is worse to lose a job than to run it twice.
      Sidekiq::Fetcher.strategy.bulk_requeue(@in_progress.values, @options)
      @in_progress.clear
    end
  end
end
