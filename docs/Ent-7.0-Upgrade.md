# Welcome to Sidekiq Enterprise 7.0

Sidekiq Enterprise 7.0 contains some breaking changes which refactor internals, remove deprecated features and update required dependency versions.

Note that major versions 3-6 were skipped in order to synchronize Sidekiq Enterprise's major version number with Sidekiq 7.

## What's New

### Refactoring internals

Sidekiq 7.0's new Embedding support required substantial refactoring of Enterprise internals.
I've tried to maintain compatibility where possible.

## Unique Locks in Version 7.0.4

Sidekiq Enterprise v7.0.4 accidentally broke data compatibility with unique
locks set by previous versions. You may see duplicate jobs for a short
period until the new-style locks are populated in Redis.

## Version Support

- Redis 6.2+ is now required
- Ruby 2.7+ is now required
- Rails 6.0+ is now supported

Support is only guaranteed for the current and previous major versions. With the release of Sidekiq Enterprise 7, Sidekiq Enterprise 1.x is no longer supported.
