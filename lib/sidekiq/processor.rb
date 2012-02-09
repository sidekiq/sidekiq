require 'celluloid'

require 'sidekiq/util'
require 'sidekiq/middleware/chain'
require 'sidekiq/middleware/server/active_record'
require 'sidekiq/middleware/server/airbrake'
require 'sidekiq/middleware/server/unique_jobs'

module Sidekiq
  class Processor
    include Util
    include Celluloid

    def self.middleware
      @middleware ||= begin
        chain = Middleware::Chain.new

        # default middleware
        chain.register do
          use Middleware::Server::UniqueJobs, Sidekiq::Client.redis
          use Middleware::Server::Airbrake
          use Middleware::Server::ActiveRecord
        end
        chain
      end
    end

    def initialize(boss)
      @boss = boss
    end

    def process(msg)
      klass  = constantize(msg['class'])
      worker = klass.new
      self.class.middleware.invoke(worker, msg) do
        worker.perform(*msg['args'])
      end
      @boss.processor_done!(current_actor)
    end

    # See http://github.com/tarcieri/celluloid/issues/22
    def inspect
      "Sidekiq::Processor<#{object_id}>"
    end
  end
end
