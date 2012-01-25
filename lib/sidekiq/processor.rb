require 'active_support/inflector'

module Sidekiq
  class Processor
    include Celluloid

    def initialize(boss)
      @boss = boss
    end

    def process(msg)
      begin
        klass = msg['class'].constantize
        klass.new.perform(*msg['args'])
        @boss.processor_done!(current_actor)
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
