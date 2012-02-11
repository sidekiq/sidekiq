require 'digest'

module Sidekiq
  module Middleware
    module Client
      class UniqueJobs
        HASH_KEY_EXPIRATION = 30 * 60

        def initialize(redis)
          @redis = redis
        end

        def call(item, queue)
          payload_hash = Digest::MD5.hexdigest(MultiJson.encode(item))
          return if already_scheduled?(payload_hash)

          @redis.setex(payload_hash, HASH_KEY_EXPIRATION, 1)

          yield
        end

        private

        def already_scheduled?(payload_hash)
          !!@redis.get(payload_hash)
        end
      end
    end
  end
end
