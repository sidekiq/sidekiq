module Sidekiq
  module Stats
    module_function

    def processed
      (Sidekiq.redis { |conn| conn.get('stat:processed') } || 0).to_i
    end

    def failed
      (Sidekiq.redis { |conn| conn.get('stat:failed') } || 0).to_i
    end

    def queues_with_sizes
      Sidekiq.redis { |conn|
        conn.smembers('queues').inject({}) { |memo, q|
          memo[q] = conn.llen("queue:#{q}")
          memo
        }.sort_by { |_, size| size }
      }
    end
  end
end
