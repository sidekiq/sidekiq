# frozen_string_literal: true

require "forwardable"
require "socket"
require "securerandom"
require "sidekiq/exception_handler"

module Sidekiq
  ##
  # This module is part of Sidekiq core and not intended for extensions.
  #

  class RingBuffer
    include Enumerable
    extend Forwardable
    def_delegators :@buf, :[], :each, :size

    def initialize(size, default = 0)
      @size = size
      @buf = Array.new(size, default)
      @index = 0
    end

    def <<(element)
      @buf[@index % @size] = element
      @index += 1
      element
    end

    def buffer
      @buf
    end

    def reset(default = 0)
      @buf.fill(default)
    end
  end

  module Util
    include ExceptionHandler

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

    def fire_event(event, options = {})
      reverse = options[:reverse]
      reraise = options[:reraise]

      arr = Sidekiq.options[:lifecycle_events][event]
      arr.reverse! if reverse
      arr.each do |block|
        block.call
      rescue => ex
        handle_exception(ex, {context: "Exception during Sidekiq lifecycle event.", event: event})
        raise ex if reraise
      end
      arr.clear
    end
  end
end
