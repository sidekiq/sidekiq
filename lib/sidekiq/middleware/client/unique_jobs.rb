require 'multi_json'
require 'digest'

module Sidekiq
  module Middleware
    module Client
      class UniqueJobs
        HASH_KEY_EXPIRATION = 30 * 60

        def call(item, queue)
          payload_hash = Digest::MD5.hexdigest(MultiJson.encode(item))
          Sidekiq.redis do |conn|
            return if conn.get(payload_hash)
            conn.setex(payload_hash, HASH_KEY_EXPIRATION, 1)
          end

          yield
        end
      end
    end
  end
end
