module Sidekiq
  module Middleware
    module Server
      class Logging

        def call(worker, item, queue)
          begin
            start = Time.now
            logger.info("start".freeze)
            yield
            logger.info("done: #{elapsed(start)} sec")
          rescue Exception
            logger.info("fail: #{elapsed(start)} sec")
            raise
          end
        end

        private

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

