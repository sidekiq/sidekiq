require "sidekiq/worker"

module Sidekiq
  # Sidekiq::Job is a new alias for Sidekiq::Worker, coming in 6.3.0.
  # You can opt into this by requiring 'sidekiq/job' in your initializer
  # and then using `include Sidekiq::Job` rather than `Sidekiq::Worker`.
  Job = Worker
end
