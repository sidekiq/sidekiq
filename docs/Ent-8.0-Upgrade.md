# Welcome to Sidekiq Enterprise 8.0

Sidekiq Enterprise 8.0 contains some breaking changes which refactor internals, remove deprecated features and update required dependency versions. See also [[8.0-Upgrade.md]] and [[Pro-8.0-Upgrade.md]].

## What's New

### Web Authorization

Sidekiq::Web supports a simple authorization scheme:

```ruby
Sidekiq::Web.authorize do |env,method,path|
  # ...
end
```

For 8.0, this has changed to:

```ruby
Sidekiq::Web.configure do |config|
  config.authorize do |env, method, path|
    # for example, read only Web UI
    method == "GET" || method == "HEAD"
  end
end
```

## Version Support

Support is only guaranteed for the current and previous major versions. With the release of Sidekiq Enterprise 8.0, Sidekiq Enterprise 2.x is no longer supported.

## Upgrading

Upgrade your Sidekiq gems with `bundle up sidekiq-ent`.
This will pull upgrades for sidekiq-pro, sidekiq and all lower-level dependent gems.

**Warning**: using `bundle up sidekiq` can lead to incompatible gem versions in use.
