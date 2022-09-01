# Welcome to Sidekiq Enterprise 3.0

Sidekiq Enterprise 3.0 contains some breaking changes which refactor internals, remove deprecated features and update required dependency versions.

## What's New

### Refactoring internals

Sidekiq 7.0's new Embedding support required substantial refactoring of Enterprise internals.
I've tried to maintain compatibility where possible.

## Version Support

- Redis 6.2+ is now required
- Ruby 2.7+ is now required
- Rails 6.0+ is now supported

Support is only guaranteed for the current and previous major versions. With the release of Sidekiq Pro 6, Sidekiq Pro 4.x is no longer supported.