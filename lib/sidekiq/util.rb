# frozen_string_literal: true

require "socket"
require "securerandom"

module Sidekiq
  ##
  # This module is part of Sidekiq core and not intended for extensions.
  #
  module Util

    def watchdog(last_words)
      yield
    rescue Exception => ex
      handle_exception(ex, {context: last_words})
      raise ex
    end

    def safe_thread(name, &block)
      Thread.new do
        Thread.current.name = name
        watchdog(name, &block)
      end
    end

    def logger
      Sidekiq.logger
    end

    def redis(&block)
      Sidekiq.redis(&block)
    end

    def tid
      Thread.current["sidekiq_tid"] ||= (Thread.current.object_id ^ ::Process.pid).to_s(36)
    end

    def hostname
      ENV["DYNO"] || Socket.gethostname
    end

    def process_nonce
      @@process_nonce ||= SecureRandom.hex(6)
    end

    def identity
      @@identity ||= "#{hostname}:#{::Process.pid}:#{process_nonce}"
    end

    def fire_event(runner, handlers, event, reverse: false, reraise: false, clearable: true)
      arr = handlers[event]
      arr.reverse! if reverse
      arr.each do |block|
        if block.arity == 0
          block.call
        else
          block.call(runner)
        end
      rescue => ex
        handle_exception(ex, {context: "Exception during Sidekiq :#{event} event.", event: event})
        raise ex if reraise
      end
      arr.clear if clearable
    end

    def handle_exception(runner, ex, ctx = {})
      error_handlers.each do |handler|
        handler.call(ex, ctx)
      rescue => ex
        logger.error "!!! ERROR HANDLER THREW AN ERROR !!!"
        logger.error ex
        logger.error ex.backtrace.join("\n") unless ex.backtrace.nil?
      end
    end

  end
end
