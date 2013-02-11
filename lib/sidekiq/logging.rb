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

    def self.initialize_logger(log_target = STDOUT)
      @logger = Logger.new(log_target)
      @logger.level = Logger::INFO
      @logger.formatter = Pretty.new
      @logger
    end

    def self.logger
      @logger || initialize_logger
    end

    def self.logger=(log)
      @logger = (log ? log : Logger.new('/dev/null'))
    end

    def logger
      Sidekiq::Logging.logger
    end
  end
end
