require 'sidekiq/util'
require 'sidekiq/middleware'
require 'celluloid'

module Sidekiq
  class Processor
    include Util
    include Celluloid

    def initialize(boss)
      @boss = boss
    end

    def process(msg, queue)
      klass = constantize(msg['class'])
      invoke_chain(klass.new, msg, queue)
      @boss.processor_done!(current_actor)
    end

    def invoke_chain(worker, msg, queue)
      chain = Sidekiq::Middleware::Chain.retrieve.dup
      traverse_chain = lambda do
        if chain.empty?
          worker.perform(*msg['args'])
        else
          chain.shift.call(worker, msg, queue, &traverse_chain)
        end
      end
      traverse_chain.call
    end

    # See http://github.com/tarcieri/celluloid/issues/22
    def inspect
      "Sidekiq::Processor<#{object_id}>"
    end
  end
end
