module Sidekiq
  module_function

  def size(*queues)
    return Sidekiq::Stats.new.enqueued if queues.empty?

    Sidekiq.redis { |conn|
      conn.multi {
        queues.map { |q| conn.llen("queue:#{q}") }
      }
    }.inject(0) { |memo, count| memo += count }
  end
end
