# Welcome to Sidekiq Pro 5.0!

Sidekiq Pro 5.0 is mainly a cleanup release for Sidekiq 6.0. The
migration should be as close to trivial as a major version bump can be.
Note that Sidekiq 6.0 does have major breaking changes.

## What's New

* New localizations for the Sidekiq Pro Web UI: ES, ZH, PT, JA, RU
* Removed deprecated APIs and warnings.
* Various changes for Sidekiq 6.0
* Requires Ruby 2.5+ and Redis 4.0+
* Requires Sidekiq 6.0+.

## Upgrade

* Upgrade to the latest Sidekiq Pro 4.x.
```ruby
gem 'sidekiq-pro', '< 5'
```
* Fix any deprecation warnings you see.
* Upgrade to 5.x.
```ruby
gem 'sidekiq-pro', '< 6'
```
