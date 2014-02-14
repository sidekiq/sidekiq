# Upgrading to Sidekiq 3.0

Sidekiq 3.0 brings several new features but also removes old APIs and
changes a few data elements in Redis.  To upgrade cleanly:

* Upgrade to the latest Sidekiq 2.x and run it for a few weeks.
  `gem 'sidekiq', '< 3'`
  This is only needed if you have retries pending.
* Remove any usage of the following APIs:
  - `Sidekiq::Client.registered\_workers` replaced by `Sidekiq::Workers.new`
  - `Sidekiq::Client.registered_queues` replaced by `Sidekiq::Queue.all`
  - `Sidekiq::Worker#retries_exhausted` replaced by `Sidekiq::Worker.sidekiq_retries_exhausted`
* Redis-to-Go is no longer transparently activated on Heroku so as to not play
  favorites with any particular Redis service. You need to set a config option
  for your app:
  `heroku config:set REDIS_PROVIDER=REDISTOGO_URL`
* Anyone using Airbrake, Honeybadger, Exceptional or ExceptionNotifier
  will need to update their error gem version to the latest to pull in
  Sidekiq support.  Sidekiq will not provide explicit support for these
  services so as to not play favorites with any particular error service.
* Ruby 1.9 is no longer officially supported.  Sidekiq's official
  support policy is to support the current and previous major releases
  of Ruby and Rails.  As of February 2014, that's Ruby 2.1, Ruby 2.0, Rails 4.0
  and Rails 3.2.  I will accept PRs to fix issues found by users.
