module Sidekiq
  module Middleware
    module Server
      class UniqueJobs
        def initialize(redis)
          @redis = redis
        end

        def call(worker, msg)
          yield
        ensure
          @redis.del(Digest::MD5.hexdigest(MultiJson.encode(msg)))
        end
      end
    end
  end
end