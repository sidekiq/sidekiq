require 'sidekiq/util'
require 'celluloid'

module Sidekiq
  class Processor
    include Util
    include Celluloid

    def initialize(boss)
      @boss = boss
    end

    def process(msg)
      begin
        klass = constantize(msg['class'])
        klass.new.perform(*msg['args'])
        @boss.processor_done!(current_actor)
      rescue => ex
        send_to_airbrake(msg, ex) if defined?(::Airbrake)
        raise ex
      end
    end

    def send_to_airbrake(msg, ex)
      ::Airbrake.notify(:error_class   => ex.class.name,
                        :error_message => "#{ex.class.name}: #{ex.message}",
                        :parameters    => msg)
    end

    # See http://github.com/tarcieri/celluloid/issues/22
    def inspect
      "Sidekiq::Processor<#{object_id}>"
    end
  end
end
