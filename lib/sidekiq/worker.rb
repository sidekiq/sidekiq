module Sidekiq
  class Worker
    include Celluloid

    def process(msg)
      begin
        klass = msg['class'].constantize
        klass.new.perform(*msg['args'])
      rescue => ex
        send_to_airbrake(msg, ex) if defined?(::Airbrake)
        raise ex
      end
    end

    def send_to_airbrake(msg, ex)
      ::Airbrake.notify(:error_class   => ex.class.name,
                        :error_message => "#{ex.class.name}: #{e.message}",
                        :parameters    => json)
    end
  end
end
