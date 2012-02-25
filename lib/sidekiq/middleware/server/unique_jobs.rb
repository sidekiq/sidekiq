module Sidekiq
  module Middleware
    module Server
      class UniqueJobs
        def call(*args)
          yield
        ensure
          Sidekiq.redis.del(Digest::MD5.hexdigest(MultiJson.encode(args[1])))
        end
      end
    end
  end
end
