# frozen_string_literal: true

require 'logger'
require 'time'

module Sidekiq
  class Logger < ::Logger

    def initialize(*args)
      super

      formatter_class = case Sidekiq.logger_formatter
      when :json
        Formatters::JSON
      else
        ENV['DYNO'] ? Formatters::WithoutTimestamp : Formatters::Pretty
      end

      self.formatter = formatter_class.new
    end

    def tid
      Thread.current['sidekiq_tid'] ||= (Thread.current.object_id ^ ::Process.pid).to_s(36)
    end

    def context
      Thread.current[:sidekiq_context] ||= {}
    end

    def with_context(hash)
      context.merge!(hash)
      yield
    ensure
      hash.keys.each { |key| context.delete(key) }
    end

    module Formatters
      class Pretty < Logger::Formatter
        def call(severity, time, program_name, message)
          "#{time.utc.iso8601(3)} #{::Process.pid} TID-#{Sidekiq.logger.tid}#{format_context(Sidekiq.logger.context)} #{severity}: #{message}\n"
        end

        private

        def format_context(context)
          ' ' + context.compact.map { |k, v| "#{k.upcase}=#{v}" }.join(' ') if context.any?
        end
      end

      class WithoutTimestamp < Pretty
        def call(severity, time, program_name, message)
          "#{::Process.pid} TID-#{Sidekiq.logger.tid}#{format_context(Sidekiq.logger.context)} #{severity}: #{message}\n"
        end
      end

      class JSON < Logger::Formatter
        def call(severity, time, program_name, message)
          Sidekiq.dump_json(
            ts: time.utc.iso8601(3),
            pid: ::Process.pid,
            tid: Sidekiq.logger.tid,
            ctx: Sidekiq.logger.context,
            sev: severity,
            msg: message
          )
        end
      end
    end
  end
end
