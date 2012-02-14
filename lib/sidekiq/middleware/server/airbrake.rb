require 'sidekiq/util'

module Sidekiq
  module Middleware
    module Server
      class Airbrake
        include Util
        def call(*args)
          yield
        rescue => ex
          logger.warn ex
          logger.warn ex.backtrace.join("\n")
          send_to_airbrake(args[1], ex) if defined?(::Airbrake)
          raise
        end

        private

        def send_to_airbrake(msg, ex)
          ::Airbrake.notify(:error_class   => ex.class.name,
                            :error_message => "#{ex.class.name}: #{ex.message}",
                            :parameters    => msg)
        end
      end
    end
  end
end



