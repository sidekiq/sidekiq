# frozen_string_literal: true
require 'time'
require 'logger'

module Sidekiq
  module Logging

    class Pretty < Logger::Formatter
      def call(severity, time, program_name, message)
        "#{time.utc.iso8601(3)} #{::Process.pid} TID-#{Sidekiq::Logging.tid}#{format_context(Sidekiq::Logging.context)} #{severity}: #{message}\n"
      end

      private

      def format_context(context)
        ' ' + context.join(' ') if context.any?
      end
    end

    class WithoutTimestamp < Pretty
      def call(severity, time, program_name, message)
        "#{::Process.pid} TID-#{Sidekiq::Logging.tid}#{format_context(Sidekiq::Logging.context)} #{severity}: #{message}\n"
      end
    end

    class JSON < Pretty
      def call(severity, time, program_name, message)
        Sidekiq.dump_json(
          timestamp: time.utc.iso8601(3),
          pid: ::Process.pid,
          tid: Sidekiq::Logging.tid,
          context: Sidekiq::Logging.context,
          severity: severity,
          message: message
        )
      end
    end

    def self.context
      Thread.current[:sidekiq_context] ||= []
    end

    def self.with_context(msg)
      context << msg
      yield
    ensure
      context.pop
    end

    def self.tid
      Thread.current['sidekiq_tid'] ||= (Thread.current.object_id ^ ::Process.pid).to_s(36)
    end

    def self.job_hash_context(job_hash)
      # If we're using a wrapper class, like ActiveJob, use the "wrapped"
      # attribute to expose the underlying thing.
      klass = job_hash['wrapped'] || job_hash["class"]
      bid = job_hash['bid']
      "#{klass} JID-#{job_hash['jid']}#{" BID-#{bid}" if bid}"
    end

    def self.with_job_hash_context(job_hash, &block)
      with_context(job_hash_context(job_hash), &block)
    end

    def self.initialize_logger(log_target = STDOUT)
      oldlogger = defined?(@logger) ? @logger : nil
      @logger = Logger.new(log_target)
      @logger.level = Logger::INFO
      @logger.formatter = ENV['DYNO'] ? WithoutTimestamp.new : Pretty.new
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
