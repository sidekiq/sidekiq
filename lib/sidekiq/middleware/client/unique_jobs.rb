require 'multi_json'
require 'digest'

module Sidekiq
  module Middleware
    module Client
      class UniqueJobs
        HASH_KEY_EXPIRATION = 30 * 60

        def call(worker_class, item, queue)
          enabled = worker_class.get_sidekiq_options['unique']
          if enabled
            payload_hash = Digest::MD5.hexdigest(MultiJson.dump(item))
            unique = false

            Sidekiq.redis do |conn|
              conn.watch(payload_hash)

              if conn.get(payload_hash)
                conn.unwatch
              else
                unique = conn.multi do
                  conn.setex(payload_hash, HASH_KEY_EXPIRATION, 1)
                end
              end
            end
            yield if unique
          else
            yield
          end
        end

      end
    end
  end
end
