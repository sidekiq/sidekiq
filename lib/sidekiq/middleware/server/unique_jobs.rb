require 'multi_json'

module Sidekiq
  module Middleware
    module Server
      class UniqueJobs
        def call(*args)
          yield
        ensure
          json = if MultiJson.respond_to?(:dump)
            MultiJson.dump(args[1])
          else
            MultiJson.encode(args[1])
          end
          hash = Digest::MD5.hexdigest(json)
          Sidekiq.redis {|conn| conn.del(hash) }
        end
      end
    end
  end
end
