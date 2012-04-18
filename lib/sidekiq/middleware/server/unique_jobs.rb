module Sidekiq
  module Middleware
    module Server
      class UniqueJobs
        def call(*args)
          yield
        ensure
          json = MultiJson.dump(args[1])
          hash = Digest::MD5.hexdigest(json)
          Sidekiq.redis {|conn| conn.del(hash) }
        end
      end
    end
  end
end
