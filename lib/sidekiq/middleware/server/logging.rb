module Sidekiq
  module Middleware
    module Server
      class Logging

        def call(worker, item, queue)
          Sidekiq::Logging.with_context("#{worker.class.to_s} JID-#{item['jid']}") do
            begin
              start = Time.now
              logger.info { "start" } if logger.level <= Logger::INFO
              yield

              # only output the finish if we're in INFO or lower, or there is a threshold and this is a long job
              t = elapsed(start)

              if logger.threshold > 0 && t > logger.threshold
                logger.warn { "done: #{t} sec" }
              elsif logger.level <= Logger::INFO
                logger.info { "done: #{t} sec" }
              end
            rescue Exception
              logger.warn { "fail: #{elapsed(start)} sec" }
              raise
            end
          end
        end

        def elapsed(start)
          (Time.now - start).to_f.round(3)
        end

        def logger
          Sidekiq.logger
        end
      end
    end
  end
end

