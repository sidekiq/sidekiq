# Sidekiq Enterprise Changelog

[Sidekiq Changes](https://github.com/mperham/sidekiq/blob/main/Changes.md) | [Sidekiq Pro Changes](https://github.com/mperham/sidekiq/blob/main/Pro-Changes.md) | [Sidekiq Enterprise Changes](https://github.com/mperham/sidekiq/blob/main/Ent-Changes.md)

Please see [sidekiq.org](https://sidekiq.org) for more details and how to buy.

2.3.1
-------------

- Fix multi/pipe deprecation in redis-rb 4.6
- Leader now elects more often, to minimize missed cron jobs
- Fix periodic jobs missing the "fallback" hour during DST changeover [#5049]

2.3.0
-------------

- Remove jQuery usage in UI tabs
- Pass exception to rate limiter backoff proc [#5024]

2.2.3
-------------

- Fixes for leaky and unlimited limiters [#4809, #4869]
- Invalid leaders now immediately step down [#4950]
- Web UI now displays "next run time" in the specified timezone [#4833]
- Fix swarm memory monitoring on BSDs

2.2.2
-------------

- Periodic job timezone fix [#4796]

2.2.1
-------------

- Support configurable timezones for periodic jobs [#4749]
- Handle edge case leading to negative expiry in uniqueness [#4763]

2.2.0
-------------

- Add new **leaky bucket** rate limiter [#4414]
  This allows clients to burst up to X calls before throttling
  back to X calls per Y seconds. To limit the user to 60 calls
  per minute:
```ruby
leaker = Sidekiq::Limiter.leaky("shopify", 60, :minute)
leaker.within_limit do
  ...
end
```
  See the Rate Limiting wiki page for more detail.
- Rate limiters may now customize their reschedule count [#4725]
  To disable rate limit reschedules, use `reschedule: 0`.
```ruby
Sidekiq::Limiter.concurrent("somename", 5, reschedule: 0)
```
- Allow filtering by name in the Rate Limiter UI [#4695]
- Add IT locale

2.1.2
-------------

- The Sidekiq Pro and Enterprise gem servers now `bundle install` much faster with **Bundler 2.2+** [#4158]
- Now that ActiveJobs support `sidekiq_options`, add support for uniqueness in AJs [#4667]

2.1.1
-------------

- Add optional **app preload** in swarm, saves even more memory [#4646]
- Fix incorrect queue tags in historical metrics [#4377]

2.1.0
-------------

- Move historical metrics to use tags rather than interpolating name [#4377]
```
sidekiq.enqueued.#{name} -> sidekiq.queue.size with tag queue:#{name}
sidekiq.latency.#{name} -> sidekiq.queue.latency with tag queue:#{name}
```
- Remove `concurrent-ruby` gem dependency [#4586]
- Add systemd `Type=notify` support for swarm [#4511]
- Length swarm's boot timeout to 60 sec [#4544]
- Add NL locale

2.0.1
-------------

- Periodic job registration API adjusted to avoid loading classes in initializer [#4271]
- Remove support for deprecated ENV variables (COUNT, MAXMEM\_MB, INDEX) in swarm code

2.0.0
-------------

- Except for the [newly required credentials](https://github.com/mperham/sidekiq/issues/4232), Sidekiq Enterprise 2.0 does
  not have any significant migration steps.
- Sidekiq Enterprise must now be started with valid license credentials. [#4232]
- Call `GC.compact` if possible in sidekiqswarm before forking [#4181]
- Changes for forward-compatibility with Sidekiq 6.0.
- Add death handler to remove any lingering unique locks [#4162]
- Backoff can now be customized per rate limiter [#4219]
- Code formatting changes for StandardRB

1.8.1
-------------

- Fix excessive lock reclaims with concurrent limiter [#4105]
- Add ES translations, see issues [#3949](https://github.com/mperham/sidekiq/issues/3949) and [#3951](https://github.com/mperham/sidekiq/issues/3951) to add your own language.

1.8.0
-------------

- Require Sidekiq Pro 4.0 and Sidekiq 5.2.
- Refactor historical metrics API to use revamped Statsd support in Sidekiq Pro
- Add a gauge to historical metrics for `default` queue latency [#4079]

1.7.2
-------------

- Add PT and JA translations
- Fix elapsed time calculations to use monotonic clock [#4000, sj26]
- Fix edge case where flapping leadership would cause old periodic
  jobs to be fired once [#3974]
- Add support for sidekiqswarm memory monitoring on FreeBSD [#3884]

1.7.1
-------------

- Fix Lua error in concurrent rate limiter under heavy contention
- Remove superfluous `freeze` calls on Strings [#3759]

1.7.0
-------------

- **NEW FEATURE** [Rolling restarts](https://github.com/mperham/sidekiq/wiki/Ent-Rolling-Restarts) - great for long running jobs!
- Adjust middleware so unique jobs that don't push aren't registered in a Batch [#3662]
- Add new unlimited rate limiter, useful for testing [#3743]
```ruby
limiter = Sidekiq::Limiter.unlimited(...any args...)
```

1.6.1
-------------

- Fix crash in rate limiter middleware when used with custom exceptions [#3604]

1.6.0
-------------

- Show process "leader" tag on Busy page, requires Sidekiq 5.0.2 [#2867]
- Capture custom metrics with the `save_history` API. [#2815]
- Implement new `unique_until: 'start'` policy option. [#3471]

1.5.4
-------------

- Fix broken Cron page in Web UI [#3458]

1.5.3
-------------

- Remove dependency on the algorithms gem [#3446]
- Allow user to specify max memory in megabytes with SIDEKIQ\_MAXMEM\_MB [#3451]
- Implement logic to detect app startup failure, sidekiqswarm will exit
  rather than try to restart the app forever [#3450]
- Another fix for doubly-encrypted arguments [#3368]

1.5.2
-------------

- Fix encrypted arguments double-encrypted by retry or rate limiting [#3368]
- Fix leak in concurrent rate limiter, run this in Rails console to clean up existing data [#3323]
```ruby
expiry = 1.month.to_i; Sidekiq::Limiter.redis { |c| c.scan_each(match: "lmtr-cfree-*") { |key| c.expire(key, expiry) } }
```

1.5.1
-------------

- Fix issue with census startup when not using Bundler configuration for
  source credentials.

1.5.0
-------------

- Add new web authorization API [#3251]
- Update all sidekiqswarm env vars to use SIDEKIQ\_ prefix [#3218]
- Add census reporting, the leader will ping contribsys nightly with aggregate usage metrics

1.4.0
-------------

- No functional changes, require latest Sidekiq and Sidekiq Pro versions

1.3.2
-------------

- Upgrade encryption to use OpenSSL's more secure GCM mode. [#3060]

1.3.1
-------------

- Fix multi-process memory monitoring on CentOS 6.x [#3063]
- Polish the new encryption feature a bit.

1.3.0
-------------

- **BETA** [New encryption feature](https://github.com/mperham/sidekiq/wiki/Ent-Encryption)
  which automatically encrypts the last argument of a Worker, aka the secret bag.

1.2.4
-------------

- Fix issue causing some minutely jobs to execute every other minute.
- Log a warning if slow periodic processing causes us to miss a clock tick.

1.2.3
-------------

- Periodic jobs could stop executing until process restart if Redis goes down [#3047]

1.2.2
-------------

- Add API to check if a unique lock is present. See [#2932] for details.
- Tune concurrent limiters to minimize thread thrashing under heavy contention. [#2944]
- Add option for tuning which Bundler groups get preloaded with `sidekiqswarm` [#3025]
```
SIDEKIQ_PRELOAD=default,production bin/sidekiqswarm ...
# Use an empty value for maximum application compatibility
SIDEKIQ_PRELOAD= bin/sidekiqswarm ...
```

1.2.1
-------------

- Multi-Process mode can now monitor the RSS memory of children and
  restart any that grow too large.  To limit children to 1GB each:
```
MAXMEM_KB=1048576 COUNT=2 bundle exec sidekiqswarm ...
```

1.2.0
-------------

- **NEW FEATURE** Multi-process mode!  Sidekiq Enterprise can now fork multiple worker
  processes, enabling significant memory savings.  See the [wiki
documentation](https://github.com/mperham/sidekiq/wiki/Ent-Multi-Process) for details.


0.7.10
-------------

- More precise gemspec dependency versioning

1.1.0
-------------

- **NEW FEATURE** Historical queue metrics, [documented in the wiki](https://github.com/mperham/sidekiq/wiki/Ent-Historical-Metrics) [#2719]

0.7.9, 1.0.2
-------------

- Window limiters can now accept arbitrary window sizes [#2686]
- Fix race condition in window limiters leading to non-stop OverLimit [#2704]
- Fix invalid overage counts when nesting concurrent limiters

1.0.1
----------

- Fix crash in periodic subsystem when a follower shuts down, thanks
  to @justinko for reporting.

1.0.0
----------

- Enterprise 1.x targets Sidekiq 4.x.
- Rewrite several features to remove Celluloid dependency.  No
  functional changes.

0.7.8
----------

- Fix `unique_for: false` [#2658]


0.7.7
----------

- Enterprise 0.x targets Sidekiq 3.x.
- Fix racy shutdown event which could lead to disappearing periodic
  jobs, requires Sidekiq >= 3.5.3.
- Add new :leader event which is fired when a process gains leadership.

0.7.6
----------

- Redesign how overrated jobs are rescheduled to avoid creating new
  jobs. [#2619]

0.7.5
----------

- Fix dynamic creation of concurrent limiters [#2617]

0.7.4
----------
- Add additional check to prevent duplicate periodic job creation
- Allow user-specified TTLs for rate limiters [#2607]
- Paginate rate limiter index page [#2606]

0.7.3
----------

- Rework `Sidekiq::Limiter` redis handling to match global redis handling.
- Allow user to customize rate limit backoff logic and handle custom
  rate limit errors.
- Fix scalability issue with Limiter index page.

0.7.2
----------

- Fix typo which prevented limiters with '0' in their names.

0.7.1
----------

- Fix issue where unique scheduled jobs can't be enqueued upon schedule
  due to the existing unique lock. [#2499]

0.7.0
----------

Initial release.
