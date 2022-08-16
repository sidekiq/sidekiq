module Sidekiq
  class Capsule
    include Sidekiq::Component

    def initialize(config)
      @config = config
      @queues = ["default"]
      @concurrency = 10
      @strict = true
    end

    def queues=(val)
      @queues = Array(val).each_with_object([]) do |qstr, memo|
        name, weight = qstr.split(",")
        @strict = false if weight.to_i > 0
        [weight.to_i, 1].max.times do
          memo << name
        end
      end
    end
  end
end
