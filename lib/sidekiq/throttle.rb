# frozen_string_literal: true

require "singleton"
require "pry"

module Sidekiq
  class Throttle
    include Singleton

    def self.add(queue, concurrency)
      instance.add(queue, concurrency)
    end

    def self.throttled_queues
      instance.throttled_queues
    end

    def self.running(queue)
      instance.running(queue)
    end

    def self.done(queue)
      instance.done(queue)
    end

    def self.run(job, &block)
      instance.run(job, block)
    end

    def add(queue, concurrency)
      key = "queue:#{queue}"
      concurrencies[key] = concurrency
    end

    def throttled_queues
      current_work = current_workset
      concurrencies.map do |key, limit|
        next if current_work[key].to_i < limit
        key
      end.compact
    end

    def running(queue)
      return unless concurrencies.key?(queue)
      Sidekiq.redis { |c| c.hincrby("throttle:currently_running", queue, 1) }
    end

    def done(queue)
      return unless concurrencies.key?(queue)
      Sidekiq.redis { |c| c.hincrby("throttle:currently_running", queue, -1) }
    end

    def run(job, block)
      running(job.queue)
      block.call(job)
      done(job.queue)
    end

    private

    attr_accessor :concurrencies, :currently_running

    def initialize
      self.concurrencies = {}
      self.currently_running = {}
    end

    def current_workset
      Sidekiq.redis { |c| c.hgetall("throttle:currently_running") }
    end
  end
end
