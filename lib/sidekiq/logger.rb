# frozen_string_literal: true

require "logger"
require "time"

module Sidekiq
  module LogContext
    def with_context(hash)
      ctx.merge!(hash)
      yield
    ensure
      hash.each_key { |key| ctx.delete(key) }
    end

    def ctx
      Thread.current[:sidekiq_context] ||= {}
    end
  end

  class Logger < ::Logger
    include LogContext

    def initialize(*args)
      super
      self.formatter = Sidekiq.log_formatter
    end

    module Formatters
      class Base < ::Logger::Formatter
        def tid
          Thread.current["sidekiq_tid"] ||= (Thread.current.object_id ^ ::Process.pid).to_s(36)
        end

        def ctx
          Thread.current[:sidekiq_context] ||= {}
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
            msg: message,
          }
          c = ctx
          hash["ctx"] = c unless c.empty?

          Sidekiq.dump_json(hash) << "\n"
        end
      end
    end
  end
end
