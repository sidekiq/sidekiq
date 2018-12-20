# frozen_string_literal: true
require 'time'
require 'logger'

module Sidekiq
  module Logging
    $stderr.puts("**************************************************")
    $stderr.puts("⛔️ WARNING: Sidekiq 6.0 changes Sidekiq::Logging context from array of strings to hash type. Please ensure your logging customizations are updated accordingly, particularly JobLogger.\nSidekiq::Logging module will be refactored to Sidekiq::Logger class and Sidekiq::Logging.job_hash_context will be moved to Sidekiq::JobLogger in Sidekiq 6.0.")
    $stderr.puts("**************************************************")

    class PrettyFormatter < Logger::Formatter
      def call(severity, time, program_name, message)
        "#{time.utc.iso8601(3)} #{::Process.pid} TID-#{Sidekiq::Logging.tid}#{format_context(Sidekiq::Logging.context)} #{severity}: #{message}\n"
      end

      private

      def format_context(context)
        ' ' + context.compact.map { |k, v| "#{k.upcase}=#{v}" }.join(' ') if context.any?
      end
    end

    class WithoutTimestampFormatter < PrettyFormatter
      def call(severity, time, program_name, message)
        "#{::Process.pid} TID-#{Sidekiq::Logging.tid}#{format_context(Sidekiq::Logging.context)} #{severity}: #{message}\n"
      end
    end

    class JSONFormatter < Logger::Formatter
      def call(severity, time, program_name, message)
        Sidekiq.dump_json(
          ts: time.utc.iso8601(3),
          pid: ::Process.pid,
          tid: Sidekiq::Logging.tid,
          ctx: Sidekiq::Logging.context,
          sev: severity,
          msg: message
        )
      end
    end

    def self.tid
      Thread.current['sidekiq_tid'] ||= (Thread.current.object_id ^ ::Process.pid).to_s(36)
    end

    def self.context
      Thread.current[:sidekiq_context] ||= {}
    end

    def self.with_context(hash)
      context.merge!(hash)
      yield
    ensure
      hash.keys.each { |key| context.delete(key) }
    end

    def self.job_hash_context(job_hash)
      # If we're using a wrapper class, like ActiveJob, use the "wrapped"
      # attribute to expose the underlying thing.
      {
        class: job_hash['wrapped'] || job_hash["class"],
        jid: job_hash['jid'],
        bid: job_hash['bid']
      }
    end

    def self.with_job_hash_context(job_hash, &block)
      with_context(job_hash_context(job_hash), &block)
    end

    def self.initialize_logger(log_target = STDOUT)
      @logger = Logger.new(log_target)
      @logger.level = Logger::INFO

      formatter_class = case Sidekiq.logger_formatter
      when :json
        JSONFormatter
      else
        ENV['DYNO'] ? WithoutTimestampFormatter : PrettyFormatter
      end

      @logger.formatter = formatter_class.new
      @logger
    end

    def self.logger
      defined?(@logger) ? @logger : initialize_logger
    end

    def self.logger=(log)
      @logger = (log ? log : Logger.new(File::NULL))
    end

    def logger
      Sidekiq::Logging.logger
    end
  end
end
