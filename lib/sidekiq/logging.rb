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

    def self.new_file_logger(file_path)
      initialize_logger(file_path)
    end

    def self.logger
      @logger ||= initialize_logger(STDOUT)
    end

    def self.logger=(log)
      @logger = (log ? log : Logger.new('/dev/null'))
    end

    def logger
      Sidekiq::Logging.logger
    end

    private

    def self.initialize_logger(log_target)
      log = Logger.new(log_target)
      log.level = Logger::INFO
      log.formatter = Pretty.new
      log
    end
  end
end
