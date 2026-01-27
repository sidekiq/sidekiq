# Welcome to Sidekiq Pro 8.0

Sidekiq Pro 8.0 contains some breaking changes which refactor internals, remove deprecated features and update required dependency versions.

## What's New

### Refactoring Batch internals

Portions of Sidekiq::Batch have been refactored to use modern Redis commands and structures.
This change in data model means that customers should upgrade to 7.3.x and run that version for several weeks to ensure no Batch data remains in Redis before upgrading to 8.0.

If you have an empty Batches page, you're safe to upgrade.
If you've run for a month, you're safe to upgrade.
If every `failinfo` key in Redis has a matching `failed` key, you're safe to upgrade.

```
% redis-cli
127.0.0.1:6379> keys b-*-fail*
1) "b-VWYf44jVYsZARw-failinfo"
2) "b-VWYf44jVYsZARw-failed"
```

Batches no longer store the error backtraces associated with their jobs, as these error backtraces are redundant with the job retry and can take a lot of space within Redis.

If you're fine with stopping sidekiq for a bit, you can run this migration to make 7.x batches compatible with 8.x

```ruby
Sidekiq.redis do |conn|
  conn.scan(match:"b-*-failinfo", count: 100, type: "hash") do |key|
    bid = key.split("-")[1]
    jids, ttl = conn.pipelined do |pipeline|
      pipeline.hkeys(key)
      pipeline.ttl(key)
    end

    conn.pipelined do |pipeline|
      pipeline.sadd("b-#{bid}-failed", jids)
      pipeline.expire("b-#{bid}-failed", ttl)
    end
  end
end
```

### Metric naming

For clarity and consistency, all Statsd metrics have been prefixed with `sidekiq.`.
If you are using a `:namespace` option to add `sidekiq.`, you can remove that namespace.

```ruby
Sidekiq.configure_server do |config|
  #config.dogstatsd = -> { Datadog::Statsd.new("localhost", 8125, namespace: "sidekiq") }
  config.dogstatsd = -> { Datadog::Statsd.new("localhost", 8125) }
end
```

## Version Support

Support is only guaranteed for the current and previous major versions. With the release of Sidekiq Pro 8, Sidekiq Pro 5.x is no longer supported.

## Upgrading

Upgrade your Sidekiq gems with `bundle up sidekiq-pro`.
This will pull upgrades for sidekiq-pro, sidekiq and all lower-level dependent gems.

**Warning**: using `bundle up sidekiq` can lead to incompatible gem versions in use.
