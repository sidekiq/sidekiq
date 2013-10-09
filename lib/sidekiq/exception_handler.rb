module Sidekiq
  module ExceptionHandler

    def handle_exception(ex, ctxHash={})
      Sidekiq.logger.warn(ctxHash) if !ctxHash.empty?
      Sidekiq.logger.warn ex
      Sidekiq.logger.warn ex.backtrace.join("\n") unless ex.backtrace.nil?
      # This list of services is getting a bit ridiculous.
      # For future error services, please add your own
      # middleware like BugSnag does:
      # https://github.com/bugsnag/bugsnag-ruby/blob/master/lib/bugsnag/sidekiq.rb
      send_to_airbrake(ctxHash, ex) if defined?(::Airbrake)
      send_to_honeybadger(ctxHash, ex) if defined?(::Honeybadger)
      send_to_exceptional(ctxHash, ex) if defined?(::Exceptional)
      send_to_exception_notifier(ctxHash, ex) if defined?(::ExceptionNotifier)
    end

    private

    def send_to_airbrake(hash, ex)
      ::Airbrake.notify_or_ignore(ex, :parameters => hash)
    end

    def send_to_honeybadger(hash, ex)
      ::Honeybadger.notify_or_ignore(ex, :parameters => hash)
    end

    def send_to_exceptional(hash, ex)
      if ::Exceptional::Config.should_send_to_api?
        ::Exceptional.context(hash)
        ::Exceptional::Remote.error(::Exceptional::ExceptionData.new(ex))
      end
    end

    def send_to_exception_notifier(hash, ex)
      ::ExceptionNotifier.notify_exception(ex, :data => {:message => hash})
    end
  end
end
