# frozen_string_literal: true

module Sidekiq
  class JobLogger
    def initialize(logger = Sidekiq.logger)
      @logger = logger
    end

    def call(item, queue)
      start = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
      @logger.info("start")

      yield

      Sidekiq::Context.add(:elapsed, elapsed(start))
      @logger.info("done")
    rescue Exception
      Sidekiq::Context.add(:elapsed, elapsed(start))
      @logger.info("fail")

      raise
    end

    def prepare(job_hash, &block)
      # If we're using a wrapper class, like ActiveJob, use the "wrapped"
      # attribute to expose the underlying thing.
      h = {
        class: job_hash["display_class"] || job_hash["wrapped"] || job_hash["class"],
        jid: job_hash["jid"]
      }
      h[:bid] = job_hash["bid"] if job_hash.has_key?("bid")
      h[:tags] = job_hash["tags"] if job_hash.has_key?("tags")

      Thread.current[:sidekiq_context] = h
      level = job_hash["log_level"]
      if level
        @logger.log_at(level, &block)
      else
        yield
      end
    ensure
      Thread.current[:sidekiq_context] = nil
    end

    private

    def elapsed(start)
      (::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - start).round(3)
    end
  end
end
