module Sidekiq
  class Worker
    include Celluloid

    def process(hash)
      begin
        klass = hash['class'].constantize
        klass.new.perform(*hash['args'])
      rescue => ex
        airbrake(json, ex) if defined?(::Airbrake)
        raise ex
      end
    end

    def airbrake(json, ex)
      ::Airbrake.notify(:error_class   => ex.class.name,
                        :error_message => "#{ex.class.name}: #{e.message}",
                        :parameters    => json)
    end
  end
end
