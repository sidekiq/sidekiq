require "sidekiq/test_api"

Sidekiq.testing!(:fake)

warn('⛔️ `require "sidekiq/testing"` is deprecated and will be removed in Sidekiq 9.0. See https://sidekiq.org/wiki/Testing#new-api', uplevel: 1)
