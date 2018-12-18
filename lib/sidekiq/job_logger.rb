# frozen_string_literal: true

module Sidekiq
  class JobLogger

    def call(item, queue)
      start = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)

      Sidekiq.logger.info("start")

      yield

      with_elapsed_time_context(start) do
        Sidekiq.logger.info("done")
      end
    rescue Exception
      with_elapsed_time_context(start) do
        Sidekiq.logger.info("fail")
      end

      raise
    end

    private

    def with_elapsed_time_context(start, &block)
      Sidekiq::Logging.with_context(elapsed_time_context(start), &block)
    end

    def elapsed_time_context(start)
      { elapsed: "#{elapsed(start)} sec" }
    end

    def elapsed(start)
      (::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - start).round(3)
    end
  end
end
