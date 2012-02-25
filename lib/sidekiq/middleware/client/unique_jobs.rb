require 'multi_json'
require 'digest'

module Sidekiq
  module Middleware
    module Client
      class UniqueJobs
        HASH_KEY_EXPIRATION = 30 * 60

        def call(item, queue)
          payload_hash = Digest::MD5.hexdigest(MultiJson.encode(item))
          Sidekiq.redis.with_connection do |redis|
            return if redis.get(payload_hash)
            redis.setex(payload_hash, HASH_KEY_EXPIRATION, 1)
          end

          yield
        end
      end
    end
  end
end
