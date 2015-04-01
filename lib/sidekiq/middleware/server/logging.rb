module Sidekiq
  module Middleware
    module Server
      class Logging

        def call(worker, item, queue)
          # If we're using a wrapper class, like ActiveJob, use the "wrapped"
          # attribute to expose the underlying thing.
          klass = item['wrapped'] || worker.class.to_s

          Sidekiq::Logging.with_context("#{klass} JID-#{item['jid']}#{" BID-#{item['bid']}" if item['bid']}") do
            begin
              start = Time.now
              logger.info { "start" }
              yield
              logger.info { "done: #{elapsed(start)} sec" }
            rescue Exception
              logger.info { "fail: #{elapsed(start)} sec" }
              raise
            end
          end
        end

        def elapsed(start)
          (Time.now - start).round(3)
        end

        def logger
          Sidekiq.logger
        end
      end
    end
  end
end

