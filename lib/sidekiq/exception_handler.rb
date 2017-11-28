# frozen_string_literal: true
require 'sidekiq'

module Sidekiq
  module ExceptionHandler

    class Logger
      def call(ex, ctxHash, options={})
        # In practice, this will only be called on exceptions so this increase
        # in complexity in selecting log level is low compared to expense of
        # the logging messages themselves.
        options = options || {}
        level = options.fetch(:level, :warn)
        Sidekiq.logger.send(level, options[:message]) if options.key?(:message)
        Sidekiq.logger.send(level, Sidekiq.dump_json(ctxHash)) if !ctxHash.empty?
        Sidekiq.logger.send(level, "#{ex.class.name}: #{ex.message}")
        Sidekiq.logger.send(level, ex.backtrace.join("\n")) unless ex.backtrace.nil?
      end

      # Set up default handler which just logs the error
      Sidekiq.error_handlers << Sidekiq::ExceptionHandler::Logger.new
    end

    def handle_exception(ex, ctxHash={}, options={})
      Sidekiq.error_handlers.each do |handler|
        begin
          arity = handler.method(:call).arity
          # new-style three argument method or fully variable arguments
          if arity == -3 || arity == -1
            handler.call(ex, ctxHash, options)
          else
            handler.call(ex, ctxHash)
          end
        rescue => ex
          Sidekiq.logger.error "!!! ERROR HANDLER THREW AN ERROR !!!"
          Sidekiq.logger.error ex
          Sidekiq.logger.error ex.backtrace.join("\n") unless ex.backtrace.nil?
        end
      end
    end
  end
end
