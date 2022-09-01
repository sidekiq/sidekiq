# Welcome to Sidekiq Pro 6.0

Sidekiq Pro 6.0 contains some breaking changes which refactor internals, remove deprecated features and update required dependency versions.

## What's New

### Refactoring internals

Sidekiq 7.0's new Embedding support required substantial refactoring of Pro internals.
I've tried to maintain compatibility where possible.

### Remove statsd

The `statsd-ruby` gem doesn't see much maintenance these days whereas the `dogstatsd-ruby` gem is active and still adding features.
For this reason, statsd support has been removed and the configuration method has changed slightly:

```ruby
Sidekiq::Pro.dogstatsd = -> { Datadog::Statsd.new("localhost", 8125) } # old way

Sidekiq.configure_server do |config|
  config.dogstatsd = -> { Datadog::Statsd.new("localhost", 8125) } # new way
end
```

## Version Support

- Redis 6.2+ is now required
- Ruby 2.7+ is now required
- Rails 6.0+ is now supported

Support is only guaranteed for the current and previous major versions. With the release of Sidekiq Pro 6, Sidekiq Pro 4.x is no longer supported.