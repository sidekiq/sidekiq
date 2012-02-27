require 'sidekiq/util'

module Sidekiq
  module Middleware
    module Server
      class ExceptionHandler
        include Util
        def call(*args)
          yield
        rescue => ex
          logger.warn ex
          logger.warn ex.backtrace.join("\n")
          send_to_airbrake(args[1], ex) if defined?(::Airbrake)
          send_to_exceptional(args[1], ex) if defined?(::Exceptional)
          send_to_exception_notifier(args[1], ex) if defined?(::ExceptionNotifier)
          raise
        end

        private

        def send_to_airbrake(msg, ex)
          ::Airbrake.notify(ex, :parameters => msg)
        end

        def send_to_exceptional(msg, ex)
          if ::Exceptional::Config.should_send_to_api?
            ::Exceptional.context(msg)
            ::Exceptional::Remote.error(::Exceptional::ExceptionData.new(ex))
          end
        end

        def send_to_exception_notifier(msg, ex)
          ::ExceptionNotifier::Notifier.background_exception_notification(e, :data => { :message => msg })
        end
      end
    end
  end
end
