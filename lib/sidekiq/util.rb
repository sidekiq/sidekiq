require 'socket'
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
      handle_exception(ex, { :context => last_words })
    end

    def logger
      Sidekiq.logger
    end

    def redis(&block)
      Sidekiq.redis(&block)
    end

    def process_id
      Process.pid
    end

    def hostname
      Socket.gethostname
    end
  end
end
