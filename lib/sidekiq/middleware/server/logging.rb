module Sidekiq
  module Middleware
    module Server
      class Logging

        def call(worker, item, queue)
          Sidekiq::Logging.with_context("#{worker.class.to_s} JID-#{item['jid']}") do
            begin
              start = Time.now
              worker.logger.info { "start" }
              yield

              elapsed = elapsed(start)
              
              # if execution_threshold is set, let's respect it with WARN on too long of job
              if worker.logger.execution_threshold && worker.logger.execution_threshold.to_f < elapsed
                worker.logger.warn { "done: #{elapsed} sec" }
              else
                worker.logger.info { "done: #{elapsed} sec" }
              end
            rescue Exception
              worker.logger.warn { "fail: #{elapsed(start)} sec" }
              raise
            end
          end
        end

        def elapsed(start)
          (Time.now - start).to_f.round(3)
        end
      end
    end
  end
end

