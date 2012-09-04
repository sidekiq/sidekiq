module Sidekiq
  module_function

  def info
    results = {}
    processed, failed, queues = Sidekiq.redis { |conn|
      conn.multi do
        conn.get('stat:processed')
        conn.get('stat:failed')
        conn.smembers('queues')
      end
    }
    results[:queues_with_sizes] = Sidekiq.redis do |conn|
      queues.inject({}) { |memo, q|
        memo[q] = conn.llen("queue:#{q}")
        memo
      }.sort_by { |_, size| size }
    end
    results[:processed] = (processed || 0).to_i
    results[:failed] = (failed || 0).to_i
    results[:backlog] = results[:queues_with_sizes].
                          map {|_, size| size }.
                          inject(0) {|memo, val| memo + val }
    results
  end

  def size(*queues)
    return info[:backlog] if queues.empty?

    Sidekiq.redis { |conn|
      conn.multi {
        queues.map { |q| conn.llen("queue:#{q}") }
      }
    }.inject(0) { |memo, count| memo += count }
  end
end
