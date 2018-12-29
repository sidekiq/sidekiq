# frozen_string_literal: true

module Sidekiq
  class JobLogger

    def initialize(logger=Sidekiq.logger)
      @logger = logger
    end

    def call(item, queue)
      start = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
      @logger.info("start")

      yield

      with_elapsed_time_context(start) do
        @logger.info("done")
      end
    rescue Exception
      with_elapsed_time_context(start) do
        @logger.info("fail")
      end

      raise
    end

    def with_job_hash_context(job_hash, &block)
      @logger.with_context(job_hash_context(job_hash), &block)
    end

    def job_hash_context(job_hash)
      # If we're using a wrapper class, like ActiveJob, use the "wrapped"
      # attribute to expose the underlying thing.
      h = {
        class: job_hash['wrapped'] || job_hash["class"],
        jid: job_hash['jid'],
      }
      h[:bid] = job_hash['bid'] if job_hash['bid']
      h
    end

    def with_elapsed_time_context(start, &block)
      @logger.with_context(elapsed_time_context(start), &block)
    end

    def elapsed_time_context(start)
      { elapsed: "#{elapsed(start)}" }
    end

    private

    def elapsed(start)
      (::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - start).round(3)
    end
  end
end
