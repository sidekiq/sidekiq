# frozen_string_literal: true

module Sidekiq
  class Config
    DEFAULTS = {
      queues: [],
      labels: [],
      concurrency: 10,
      require: ".",
      strict: true,
      environment: nil,
      timeout: 25,
      poll_interval_average: nil,
      average_scheduled_poll_interval: 5,
      on_complex_arguments: :warn,
      error_handlers: [],
      death_handlers: [],
      lifecycle_events: {
        startup: [],
        quiet: [],
        shutdown: [],
        heartbeat: []
      },
      dead_max_jobs: 10_000,
      dead_timeout_in_seconds: 180 * 24 * 60 * 60, # 6 months
      reloader: proc { |&block| block.call }
    }

    DEFAULT_WORKER_OPTIONS = {
      "retry" => true,
      "queue" => "default"
    }.freeze

    attr_accessor :options, :default_worker_options

    def initialize
      self.options = DEFAULTS.dup
      self.default_worker_options = DEFAULT_WORKER_OPTIONS
    end

    def merge_default_worker_options(options)
      self.default_worker_options = default_worker_options.merge(options.transform_keys(&:to_s))
    end
  end
end
