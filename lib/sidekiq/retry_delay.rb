module Sidekiq
  class RetryDelay
    attr_reader :delay_with, :count, :logger

    def initialize(count, delay_with, logger)
      @count      = count
      @delay_with = delay_with
      @logger     = logger
    end

    def seconds_to_delay
      user_defined_delay || default_delay
    end

    private
    def default_delay
      (count ** 4) + 15 + (rand(30)*(count+1))
    end

    def user_defined_delay
      delay_with.call(count) if delay_with.respond_to?(:call)
    rescue Exception => e
      logger.error { "Failure scheduling retry using the defined `sidekiq_retry_in`, falling back to the default! #{e.message}"}
    end
  end
end
