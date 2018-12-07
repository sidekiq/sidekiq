# frozen_string_literal: true
require 'time'
require 'logger'
require 'fcntl'

module Sidekiq
  module Logging

    class Pretty < Logger::Formatter
      SPACE = " "

      # Provide a call() method that returns the formatted message.
      def call(severity, time, program_name, message)
        "#{time.utc.iso8601(3)} #{::Process.pid} TID-#{Sidekiq::Logging.tid}#{context} #{severity}: #{message}\n"
      end

      def context
        c = Thread.current[:sidekiq_context]
        " #{c.join(SPACE)}" if c && c.any?
      end
    end

    class WithoutTimestamp < Pretty
      def call(severity, time, program_name, message)
        "#{::Process.pid} TID-#{Sidekiq::Logging.tid}#{context} #{severity}: #{message}\n"
      end
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

    def self.with_context(msg)
      Thread.current[:sidekiq_context] ||= []
      Thread.current[:sidekiq_context] << msg
      yield
    ensure
      Thread.current[:sidekiq_context].pop
    end

    def self.initialize_logger
      return @logger if defined?(@logger)
      @logger = Logger.new(STDOUT)
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
