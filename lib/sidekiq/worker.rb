module Sidekiq
  class Worker
    include Celluloid

    def process(json)
      klass = json['class'].constantize
      klass.new.perform(*json['args'])
    end
  end
end
