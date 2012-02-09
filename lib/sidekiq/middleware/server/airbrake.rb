module Sidekiq
  module Middleware
    module Server
      class Airbrake
        def call(worker, msg)
          yield
        rescue => ex
          send_to_airbrake(msg, ex) if defined?(::Airbrake)
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



