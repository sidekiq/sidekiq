module Sidekiq
  module Stats
    module_function

    def processed
      (Sidekiq.redis { |conn| conn.get('stat:processed') } || 0).to_i
    end

    def failed
      (Sidekiq.redis { |conn| conn.get('stat:failed') } || 0).to_i
    end
  end
end
