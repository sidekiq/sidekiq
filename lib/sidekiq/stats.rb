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

    def backlog
      queues_with_sizes.map {|_, size| size }.inject(0) {|memo, val| memo + val }
    end

    def size(*queues)
      return backlog if queues.empty?
      queues.
        map(&:to_s).
        inject(0) { |memo, queue|
          memo += Sidekiq.redis { |conn| conn.llen("queue:#{queue}") }
        }
    end
  end
end
