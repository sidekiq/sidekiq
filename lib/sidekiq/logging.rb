require 'time'
require 'logger'

module Sidekiq
  module Logging

    class Pretty < Logger::Formatter
      # Provide a call() method that returns the formatted message.
      def call(severity, time, program_name, message)
        "#{time.utc.iso8601} #{Process.pid} TID-#{Thread.current.object_id.to_s(36)}#{context} #{severity}: #{message}\n"
      end

      def context
        c = Thread.current[:sidekiq_context]
        c ? " #{c}" : ''
      end
    end

    def self.with_context(msg)
      begin
        Thread.current[:sidekiq_context] = msg
        yield
      ensure
        Thread.current[:sidekiq_context] = nil
      end
    end

    def self.logger
      @logger ||= begin
        log = Logger.new(STDOUT)
        log.level = Logger::INFO
        log.formatter = Pretty.new
        log
      end
    end

    def self.logger=(log)
      @logger = (log ? log : Logger.new('/dev/null'))
    end

    def logger
      Sidekiq::Logging.logger
    end

  end
end
