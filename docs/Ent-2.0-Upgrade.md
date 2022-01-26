# Welcome to Sidekiq Enterprise 2.0!

Sidekiq Enterprise 2.0 adds a few new features and adds the requirement that license
credentials be available at runtime.  Note that Sidekiq 6.0 does have major breaking changes.

## What's New

* Sidekiq Enterprise now requires license credentials at runtime.  If you
  configured Bundler as described in the access email you need do
nothing, everything should just work.  If you are vendoring Sidekiq
Enterprise you will need to configure Bundler also or set
`SIDEKIQ_ENT_USERNAME=abcdef12 bundle exec sidekiq...` when starting the
process. [#4232]
* Dead jobs now release any unique locks they were holding when they died [#4162]
* Backoff can now be customized per rate limiter by passing in a Proc [#4219]
```ruby
limiter = Sidekiq::Limiter.bucket(:stripe, 10, :second, backoff: ->(limiter, job) {
  return job['overrated'] || 5 # wait for N seconds, where N is the number of
                               # times we've failed the rate limit
})
```
* Removed deprecated APIs and warnings.
* Various changes for Sidekiq 6.0
* Requires Ruby 2.5+ and Redis 4.0+
* Requires Sidekiq 6.0+ and Sidekiq Pro 5.0+

## Upgrade

* Upgrade to the latest Sidekiq Enterprise 1.x.
```ruby
gem 'sidekiq-ent', '< 2'
```
* Fix any deprecation warnings you see.
* Upgrade to 2.x.
```ruby
gem 'sidekiq-ent', '< 3'
```
