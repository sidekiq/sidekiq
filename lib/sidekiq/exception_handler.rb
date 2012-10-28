module Sidekiq
  module ExceptionHandler

    def handle_exception(ex, msg)
      Sidekiq.logger.warn msg
      Sidekiq.logger.warn ex
      Sidekiq.logger.warn ex.backtrace.join("\n")
      # This list of services is getting a bit ridiculous.
      # For future error services, please add your own
      # middleware like BugSnag does:
      # https://github.com/bugsnag/bugsnag-ruby/blob/master/lib/bugsnag/sidekiq.rb
      send_to_airbrake(msg, ex) if defined?(::Airbrake)
      send_to_honeybadger(msg, ex) if defined?(::Honeybadger)
      send_to_exceptional(msg, ex) if defined?(::Exceptional)
      send_to_exception_notifier(msg, ex) if defined?(::ExceptionNotifier)
    end

    private

    def send_to_airbrake(msg, ex)
      ::Airbrake.notify_or_ignore(ex, :parameters => msg)
    end

    def send_to_honeybadger(msg, ex)
      ::Honeybadger.notify_or_ignore(ex, :parameters => msg)
    end

    def send_to_exceptional(msg, ex)
      if ::Exceptional::Config.should_send_to_api?
        ::Exceptional.context(msg)
        ::Exceptional::Remote.error(::Exceptional::ExceptionData.new(ex))
      end
    end

    def send_to_exception_notifier(msg, ex)
      ::ExceptionNotifier::Notifier.background_exception_notification(ex, :data => { :message => msg }).deliver
    end
  end
end
