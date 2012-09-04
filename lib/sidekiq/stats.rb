module Sidekiq
  module_function

  def info
    results = {}
    futures = {}
    queues_with_sizes = Sidekiq.redis { |conn|
      conn.pipelined do
        futures[:processed] = conn.get('stat:processed')
        futures[:failed] = conn.get('stat:failed')
        futures[:queues] = conn.smembers('queues')
      end
    }
    queues_with_sizes = Sidekiq.redis do |conn|
      futures[:queues].value.inject({}) { |memo, q|
        memo[q] = conn.llen("queue:#{q}")
        memo
      }.sort_by { |_, size| size }
    end
    results[:processed] = (futures[:processed].value || 0).to_i
    results[:failed] = (futures[:failed].value || 0).to_i
    results[:backlog] = queues_with_sizes.
                          map {|_, size| size }.
                          inject(0) {|memo, val| memo + val }
    results
  end

  def queues_with_sizes
    Sidekiq.redis { |conn|
      conn.smembers('queues').inject({}) { |memo, q|
        memo[q] = conn.llen("queue:#{q}")
        memo
      }.sort_by { |_, size| size }
    }
  end

  def size(*queues)
    return info[:backlog] if queues.empty?
    queues.
      map(&:to_s).
      inject(0) { |memo, queue|
        memo += Sidekiq.redis { |conn| conn.llen("queue:#{queue}") }
      }
  end
end
