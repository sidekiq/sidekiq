module Sidekiq
  class JobLogger

    def call(item, queue)
      Sidekiq::Logging.with_context(log_context(item)) do
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
    end

    private

    # If we're using a wrapper class, like ActiveJob, use the "wrapped"
    # attribute to expose the underlying thing.
    def log_context(item)
      klass = item['wrapped'.freeze] || item["class".freeze]
      "#{klass} JID-#{item['jid'.freeze]}#{" BID-#{item['bid'.freeze]}" if item['bid'.freeze]}"
    end

    def elapsed(start)
      (Time.now - start).round(3)
    end

    def logger
      Sidekiq.logger
    end
  end
end

