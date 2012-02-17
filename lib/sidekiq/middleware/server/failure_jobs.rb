module Sidekiq
  module Middleware
    module Server
      class FailureJobs
        def initialize(redis)
          @redis = redis
        end

        def call(*args)
          yield
        rescue => e
          data = {
            :failed_at => Time.now.strftime("%Y/%m/%d %H:%M:%S %Z"),
            :payload => args[1],
            :exception => e.class.to_s,
            :error => e.to_s,
            :backtrace => e.backtrace,
            :worker => args[1]['class'],
            :queue => args[2]
          }
          
          @redis.rpush(:failed, MultiJson.encode(data))
          raise
        end
      end
    end
  end
end
