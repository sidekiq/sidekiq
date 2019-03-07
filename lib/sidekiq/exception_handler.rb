# frozen_string_literal: true

require "sidekiq"

module Sidekiq
  module ExceptionHandler
    class Logger
      def call(ex, ctx)
        Sidekiq.logger.warn(Sidekiq.dump_json(ctx)) unless ctx.empty?
        Sidekiq.logger.warn("#{ex.class.name}: #{ex.message}")
        Sidekiq.logger.warn(ex.backtrace.join("\n")) unless ex.backtrace.nil?
      end

      Sidekiq.error_handlers << Sidekiq::ExceptionHandler::Logger.new
    end

    def handle_exception(ex, ctx = {})
      Sidekiq.error_handlers.each do |handler|
        handler.call(ex, ctx)
      rescue => ex
        Sidekiq.logger.error "!!! ERROR HANDLER THREW AN ERROR !!!"
        Sidekiq.logger.error ex
        Sidekiq.logger.error ex.backtrace.join("\n") unless ex.backtrace.nil?
      end
    end
  end
end
