require 'logger'

module Sidekiq
  module Util

    def self.logger
      @logger ||= begin
        log = Logger.new(STDERR)
        log.level = Logger::INFO
        log
      end
    end

    def self.logger=(log)
      @logger = (log ? log : Logger.new('/dev/null'))
    end

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
      Sidekiq::Util.logger
    end

    def redis
      Sidekiq::Manager.redis
    end
  end
end
