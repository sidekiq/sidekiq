require "sidekiq"

module SidekiqExt
  class RedisInfo
    include Enumerable

    def initialize
      @info = Sidekiq.default_configuration.redis_info
    end

    def each(&block)
      @info.each(&block)
    end
  end
end
