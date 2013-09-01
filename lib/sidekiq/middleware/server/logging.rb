module Sidekiq
  module Middleware
    module Server
      class Logging

        def call(worker, item, queue)
          Sidekiq::Logging.with_context("#{worker.class.to_s} JID-#{item['jid']}") do
            begin
              start = Time.now
              logger.info { "start" } if log_level(worker) <= Logger::INFO
              yield

              # only output the finish if we're in INFO or lower, or there is a threshold and this is a long job
              t = elapsed(start)

              if t > log_threshold(worker) || log_level(worker) <= Logger::INFO
                logger.info { "done: #{t} sec" }
              end
            rescue Exception
              logger.info { "fail: #{elapsed(start)} sec" }
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

        def log_level(worker)
          worker.class.get_sidekiq_options['log_level'] || Logger::INFO
        end

        def log_threshold(worker)
          worker.class.get_sidekiq_options['log_threshold'] || 0
        end
      end
    end
  end
end

