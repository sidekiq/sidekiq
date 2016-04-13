require 'socket'
require 'securerandom'
require 'sidekiq/exception_handler'
require 'sidekiq/core_ext'

module Sidekiq
  ##
  # This module is part of Sidekiq core and not intended for extensions.
  #
  module Util
    include ExceptionHandler

    EXPIRY = 60 * 60 * 24

    def watchdog(last_words)
      yield
    rescue Exception => ex
      handle_exception(ex, { context: last_words })
      raise ex
    end

    def safe_thread(name, &block)
      Thread.new do
        watchdog(name, &block)
      end
    end

    def logger
      Sidekiq.logger
    end

    def redis(&block)
      Sidekiq.redis(&block)
    end

    def hostname
      ENV['DYNO'] || Socket.gethostname
    end

    def process_nonce
      @@process_nonce ||= SecureRandom.hex(6)
    end

    def identity
      @@identity ||= "#{hostname}:#{$$}:#{process_nonce}"
    end

    def fire_event(event, reverse=false)
      arr = Sidekiq.options[:lifecycle_events][event]
      arr.reverse! if reverse
      arr.each do |block|
        begin
          block.call
        rescue => ex
          handle_exception(ex, { event: event })
        end
      end
      arr.clear
    end
  end
end
