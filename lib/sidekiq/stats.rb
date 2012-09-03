module Sidekiq
  module Stats
    module_function

    def processed
      Sidekiq.redis { |conn| conn.get('stat:processed') }.to_i || 0
    end
  end
end
