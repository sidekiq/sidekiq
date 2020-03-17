# frozen_string_literal: true

require "logger"
require "time"

module Sidekiq
  module Context
    def self.with(hash)
      current.merge!(hash)
      yield
    ensure
      hash.each_key { |key| current.delete(key) }
    end

    def self.current
      Thread.current[:sidekiq_context] ||= {}
    end
  end

  module LoggingUtils
    LEVELS = {
      "debug" => 0,
      "info" => 1,
      "warn" => 2,
      "error" => 3,
      "fatal" => 4
    }
    LEVELS.default_proc = proc do |_, level|
      Sidekiq.logger.warn("Invalid log level: #{level.inspect}")
      nil
    end

    def debug?
      level <= 0
    end

    def info?
      level <= 1
    end

    def warn?
      level <= 2
    end

    def error?
      level <= 3
    end

    def fatal?
      level <= 4
    end

    def local_level
      Thread.current[:sidekiq_log_level]
    end

    def local_level=(level)
      case level
      when Integer
        Thread.current[:sidekiq_log_level] = level
      when Symbol, String
        Thread.current[:sidekiq_log_level] = LEVELS[level.to_s]
      when nil
        Thread.current[:sidekiq_log_level] = nil
      else
        raise ArgumentError, "Invalid log level: #{level.inspect}"
      end
    end

    def level
      local_level || super
    end

    # Change the thread-local level for the duration of the given block.
    def log_at(level)
      old_local_level = local_level
      self.local_level = level
      yield
    ensure
      self.local_level = old_local_level
    end

    # Redefined to check severity against #level, and thus the thread-local level, rather than +@level+.
    # FIXME: Remove when the minimum Ruby version supports overriding Logger#level.
    def add(severity, message = nil, progname = nil, &block)
      severity ||= ::Logger::UNKNOWN
      progname ||= @progname

      return true if @logdev.nil? || severity < level

      if message.nil?
        if block_given?
          message = yield
        else
          message = progname
          progname = @progname
        end
      end

      @logdev.write format_message(format_severity(severity), Time.now, progname, message)
    end
  end

  class Logger < ::Logger
    include LoggingUtils

    def initialize(*args, **kwargs)
      super
      self.formatter = Sidekiq.log_formatter
    end

    module Formatters
      class Base < ::Logger::Formatter
        def tid
          Thread.current["sidekiq_tid"] ||= (Thread.current.object_id ^ ::Process.pid).to_s(36)
        end

        def ctx
          Sidekiq::Context.current
        end

        def format_context
          if ctx.any?
            " " + ctx.compact.map { |k, v|
              case v
              when Array
                "#{k}=#{v.join(",")}"
              else
                "#{k}=#{v}"
              end
            }.join(" ")
          end
        end
      end

      class Pretty < Base
        def call(severity, time, program_name, message)
          "#{time.utc.iso8601(3)} pid=#{::Process.pid} tid=#{tid}#{format_context} #{severity}: #{message}\n"
        end
      end

      class WithoutTimestamp < Pretty
        def call(severity, time, program_name, message)
          "pid=#{::Process.pid} tid=#{tid}#{format_context} #{severity}: #{message}\n"
        end
      end

      class JSON < Base
        def call(severity, time, program_name, message)
          hash = {
            ts: time.utc.iso8601(3),
            pid: ::Process.pid,
            tid: tid,
            lvl: severity,
            msg: message
          }
          c = ctx
          hash["ctx"] = c unless c.empty?

          Sidekiq.dump_json(hash) << "\n"
        end
      end
    end
  end
end
