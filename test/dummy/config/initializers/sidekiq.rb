# frozen_string_literal: true

# Do not print logs when running tests.
Sidekiq.logger.level = :fatal
