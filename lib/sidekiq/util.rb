module Sidekiq
  ##
  # This module is part of Sidekiq core and not intended for extensions.
  #
  module Util

    EXPIRY = 24 * 60 * 60

    def constantize(camel_cased_word)
      names = camel_cased_word.split('::')
      names.shift if names.empty? || names.first.empty?

      constant = Object
      names.each do |name|
        constant = constant.const_defined?(name) ? constant.const_get(name) : constant.const_missing(name)
      end
      constant
    end

    def watchdog(last_words)
      yield
    rescue => ex
      logger.error last_words
      logger.error ex
      logger.error ex.backtrace.join("\n")
    end

    def logger
      Sidekiq::Logger.logger
    end

    def redis(&block)
      Sidekiq.redis(&block)
    end

    def process_id
      Process.pid
    end
  end
end
