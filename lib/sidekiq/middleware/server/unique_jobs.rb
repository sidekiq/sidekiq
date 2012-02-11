module Sidekiq
  module Middleware
    module Server
      class UniqueJobs
        def initialize(redis)
          @redis = redis
        end

        def call(*args)
          yield
        ensure
          @redis.del(Digest::MD5.hexdigest(MultiJson.encode(args[1])))
        end
      end
    end
  end
end
