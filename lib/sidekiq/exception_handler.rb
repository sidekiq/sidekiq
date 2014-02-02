module Sidekiq
  module ExceptionHandler

    def handle_exception(ex, ctxHash={})
      Sidekiq.logger.warn(ctxHash) if !ctxHash.empty?
      Sidekiq.logger.warn ex
      Sidekiq.logger.warn ex.backtrace.join("\n") unless ex.backtrace.nil?
    end

  end
end
