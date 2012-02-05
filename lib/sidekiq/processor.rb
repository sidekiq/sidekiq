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

    def process(msg)
      klass = constantize(msg['class'])
      invoke_chain(klass.new, msg) do |worker, msg|
        worker.perform(*msg['args'])
      end
    end

    def invoke_chain(worker, msg, &block)
      invoke_link(0, worker, msg, &block)
      @boss.processor_done!(current_actor)
    end

    def invoke_link(idx, worker, msg, &block)
      chain = Sidekiq::Middleware::Chain.retrieve
      if chain.size == idx
        block.call(worker, msg)
      else
        chain[idx].call(worker, msg) do
          invoke_link(idx + 1, worker, msg, &block)
        end
      end
    end

    # See http://github.com/tarcieri/celluloid/issues/22
    def inspect
      "Sidekiq::Processor<#{object_id}>"
    end
  end
end
