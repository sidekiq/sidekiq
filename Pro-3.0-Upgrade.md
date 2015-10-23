# Welcome to Sidekiq Pro 3.0!

Sidekiq Pro 3.0 is designed to work with Sidekiq 4.0.

## What's New

* **Redis 2.8.0 or greater is required.**  Redis 2.8 was released two years
  ago and contains **many** useful features which Sidekiq couldn't
  leverage until now.  **Redis 3.0.3 or greater is recommended** for large
  scale use.

* Sidekiq Pro no longer uses Celluloid.  If your application code uses Celluloid,
  you will need to pull it in yourself.

* Pausing and unpausing queues is now instantaneous, no more polling!

* Reliable fetch has been re-implemented due to the fetch changes in
  Sidekiq 4.0.

* Support for platforms without persistent hostnames.  Since reliable fetch
  normally requires a persistent hostname, you may disable hostname usage on
  platforms like Heroku and Docker:
```ruby
Sidekiq.configure_server do |config|
  config.options[:ephemeral_hostname] = true
  config.reliable_fetch!
end
```
  This option is enabled automatically if Heroku's DYNO environment variable is present.
  Without a persistent hostname, each Sidekiq process **must** have its own unique index.

* The old 'sidekiq/notifications' features have been removed.

## Upgrade

First, make sure you are using Redis 2.8 or greater. Next:

* Upgrade to the latest Sidekiq Pro 2.x.
```ruby
gem 'sidekiq-pro', '< 3'
```
* Fix any deprecation warnings you see.
* Upgrade to 3.x.
```ruby
gem 'sidekiq-pro', '< 4'
```
