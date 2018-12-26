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

    def with_job_hash_context(job_hash, &block)
      Sidekiq.logger.with_context(job_hash_context(job_hash), &block)
    end

    def job_hash_context(job_hash)
      # If we're using a wrapper class, like ActiveJob, use the "wrapped"
      # attribute to expose the underlying thing.
      {
        class: job_hash['wrapped'] || job_hash["class"],
        jid: job_hash['jid'],
        bid: job_hash['bid']
      }
    end

    def with_elapsed_time_context(start, &block)
      Sidekiq.logger.with_context(elapsed_time_context(start), &block)
    end

    def elapsed_time_context(start)
      { elapsed: "#{elapsed(start)} sec" }
    end

    private

    def elapsed(start)
      (::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - start).round(3)
    end
  end
end
