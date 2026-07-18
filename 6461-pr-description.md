# Add operational instrumentation handlers (#6461)

Fixes #6461

**Draft** — addressing review feedback before requesting re-review.

Operational events that were previously **log-only** can now be subscribed to via `instrumentation_handlers`. Existing log output is unchanged — instrumentation is additive.

Core API is **standalone** (no ActiveSupport dependency). When Sidekiq runs inside Rails, events are optionally forwarded to `ActiveSupport::Notifications` via `Sidekiq::Rails::Instrumentation::ActiveSupportBridge`.

## Motivation

Sidekiq already exposes hooks for **errors**:

- `config.error_handlers` — exceptions during job processing
- `config.death_handlers` — jobs that exhausted retries

Operational **signals** (slow Redis RTT, slow iterable iterations, forced shutdown, Redis recovery) were only written to the log. Instrumentation gems often patch `Sidekiq::Processor`, middleware, or other internals — fragile and hard to maintain.

This PR adds `instrumentation_handlers`, similar to `error_handlers`, so apps and gems can react without patching Sidekiq. Warnings are the first category of events; Sidekiq Pro and Enterprise can publish additional instrumentation through the same API.

## Architecture

```
Plain Ruby app
  └── config.instrumentation_handlers  →  your handler

Rails app
  └── config.instrumentation_handlers  →  your handler
  └── Sidekiq::Rails::Instrumentation::ActiveSupportBridge  (auto-registered)
        └── ActiveSupport::Notifications.instrument(...)
```

Core files:

- `lib/sidekiq/config.rb` — `instrumentation_handlers`, `instrument` (`# :nodoc:`)
- `lib/sidekiq/component.rb` — `instrument` delegate

Rails integration (loaded only when Rails is present):

- `lib/sidekiq/rails/instrumentation.rb` — `ActiveSupportBridge`
- `lib/sidekiq/rails.rb` — registers bridge on server boot

No `activesupport` dependency in the gemspec. No constants module — event names are strings at call sites.

## Naming note

`instrumentation_handlers` is intentionally broader than "warnings". v1 OSS publishes mostly operational warnings, but the hook is the envelope for timings, counters, state transitions, and other operational signals later (including Pro/Ent).

## API stability

Event names and payload keys are intended to be a supported, long-term contract once merged. New payload keys may be added in the future; existing keys should remain stable.

## Handler execution

Handlers run synchronously on the calling thread, matching `error_handlers`. A slow handler can add latency on the instrumented code paths (operational events, not the per-job hot loop). Handler failures are isolated and logged so they do not interrupt Sidekiq processing.

## API

### Register handlers (plain Ruby / any app)

Handlers are registered on the **server** config (events are published from Sidekiq worker processes):

```ruby
Sidekiq.configure_server do |config|
  config.instrumentation_handlers << ->(name, payload, cfg) do
    puts "[sidekiq] #{name} #{payload.inspect}"
  end
end
```

**Handler signature:** `(name, payload, config)`

| Argument  | Type   | Description                                |
|-----------|--------|--------------------------------------------|
| `name`    | String | e.g. `"slow_rtt.sidekiq"`                  |
| `payload` | Hash   | Structured metadata (JSON-friendly values) |
| `config`  | Config | The `Sidekiq::Config` instance             |

Multiple handlers are supported. If one handler raises, Sidekiq logs the failure and continues with the remaining handlers (same isolation model as `error_handlers`).

```ruby
class MyInstrumentationHandler
  def call(name, payload, config)
    StatsD.increment(name, tags: ["event:#{name}"])
  end
end

Sidekiq.configure_server do |config|
  config.instrumentation_handlers << MyInstrumentationHandler.new
end
```

### Publish events (internal / extensions)

Sidekiq components call `instrument(name, payload)` via `Sidekiq::Component` (`# :nodoc:`). Parallel to `fire_event` for lifecycle, but separate API. Pro/Ent can use the same mechanism:

```ruby
# Example future usage in sidekiq-pro (not part of this PR)
instrument("super_fetch.reclaimed.sidekiq", { jid: "...", queue: "default" })
```

## Rails / ActiveSupport::Notifications

When Sidekiq runs inside Rails, `Sidekiq::Rails::Instrumentation::ActiveSupportBridge` is registered automatically from `sidekiq/rails.rb`. No extra setup required.

Subscribe to a specific event:

```ruby
# config/initializers/sidekiq_instrumentation.rb
subscriber = ActiveSupport::Notifications.subscribe("slow_rtt.sidekiq") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)

  Rails.logger.warn(
    "Sidekiq Redis RTT degraded: readings=#{event.payload[:readings].inspect}"
  )
end

at_exit { ActiveSupport::Notifications.unsubscribe(subscriber) }
```

Subscribe to all Sidekiq instrumentation:

```ruby
subscriber = ActiveSupport::Notifications.subscribe(/\.sidekiq\z/) do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  Rails.logger.info("[sidekiq] #{event.name} #{event.payload.inspect}")
end
```

Custom handler alongside the Rails bridge:

```ruby
Sidekiq.configure_server do |config|
  config.instrumentation_handlers << ->(name, payload, _cfg) do
    Lapsoss.report(name, context: payload) if name == "hard_shutdown.sidekiq"
  end
end
```

Non-Rails apps: use `instrumentation_handlers` directly. No ActiveSupport bridge is registered unless you add one yourself.

## Published events (OSS v1)

Event names follow Rails convention: `name.sidekiq`.

| Event | When | Payload |
|-------|------|---------|
| `slow_rtt.sidekiq` | Last 5 Redis RTT samples all exceed 50,000µs | `{ readings:, threshold:, identity: }` |
| `slow_iteration.sidekiq` | Iterable iteration exceeds `config[:timeout]` (default 25s) | `{ class:, jid:, duration:, timeout:, cursor: }` |
| `hard_shutdown.sidekiq` | Shutdown timeout expires; busy threads force-killed | `{ thread_count:, job_count: }` |
| `redis_recovered.sidekiq` | Redis fetch failures recover | `{ downtime: }` (seconds) |

Example payloads:

```ruby
# slow_rtt.sidekiq
{ readings: [52000, 61000, 58000, 55000, 60000], threshold: 50000, identity: "myhost:12345:abc123" }

# slow_iteration.sidekiq
{ class: "MyIterableJob", jid: "b4f8c2...", duration: 32.5, timeout: 25, cursor: 42 }

# hard_shutdown.sidekiq
{ thread_count: 3, job_count: 3 }

# redis_recovered.sidekiq
{ downtime: 12.4 }
```

Boot-time configuration checks (e.g. Redis `maxmemory-policy`) are intentionally excluded from v1 — they fire once per process and remain log warnings only.

## Out of scope (this PR)

- Job perform timing (overlaps OSS metrics + Pro Statsd middleware)
- Job errors (already via `error_handlers` / `death_handlers`)
- Lifecycle callbacks (`config.on(:startup)` / `fire_event`)
- Boot-time configuration warnings (e.g. Redis eviction policy)
- Client-side enqueue events

## Open questions for reviewers

1. `instrumentation_handlers` / `instrument` — acceptable, or prefer a different publish verb if `instrument` feels too APM-like?
2. Event naming — `.sidekiq` suffix (Rails AS style) vs `sidekiq.*` prefix?
3. Payload shapes — flat and JSON-friendly; fields to add/remove?
4. `redis_recovered.sidekiq` is logged at `info`, not `warn` — keep in v1 or defer?
5. Extension model — sufficient for Pro/Ent to publish via `instrument`?

## Manual testing

Validated locally in both non-Rails and Rails environments.

### Non-Rails (standalone core)

```bash
cd /path/to/sidekiq
bundle exec ruby -Ilib -e '
require "sidekiq"
cfg = Sidekiq.default_configuration
cfg.instrumentation_handlers.clear
cfg.instrumentation_handlers << ->(name, payload, _cfg) { puts "#{name} => #{payload.inspect}" }
cfg.instrument("slow_rtt.sidekiq", readings: [60_000], threshold: 50_000)
'
```

Expected: `slow_rtt.sidekiq => {readings: [60000], threshold: 50000}`

No ActiveSupport bridge is registered.

### Rails (in-repo `myapp`)

**Handlers + AS bridge** (`rails runner`):

```bash
cd myapp
bundle exec rails runner '
require "sidekiq/rails/instrumentation"
cfg = Sidekiq.default_configuration
cfg.instrumentation_handlers.clear
cfg.instrumentation_handlers << ->(name, payload, _cfg) { puts "[HANDLER] #{name} #{payload.inspect}" }
cfg.instrumentation_handlers << Sidekiq::Rails::Instrumentation::ActiveSupportBridge.new
sub = ActiveSupport::Notifications.subscribe("slow_iteration.sidekiq") { |*args|
  e = ActiveSupport::Notifications::Event.new(*args)
  puts "[AS] #{e.name} #{e.payload.inspect}"
}
cfg.instrument("slow_iteration.sidekiq", class: "TestJob", jid: "abc", duration: 6.0, timeout: 5)
ActiveSupport::Notifications.unsubscribe(sub)
'
```

**Live Sidekiq** — temporary initializer + iterable test job (`sleep(6)`, `config[:timeout] = 5`), then:

```bash
bundle exec sidekiq          # terminal 1 — restart after adding initializers
bundle exec rails runner "SlowIterationTestJob.perform_async"  # terminal 2
```

Expected: handler + AS notification + existing WARN log for `slow_iteration.sidekiq`.

## Test plan

- [x] `bundle exec ruby -Itest test/instrumentation_test.rb`
- [x] `bundle exec ruby -Itest test/rails_instrumentation_test.rb`
- [x] Non-Rails smoke test (`instrument` via `ruby -Ilib`)
- [x] Rails: `instrumentation_handlers` + `ActiveSupport::Notifications` via `rails runner`
- [x] Rails live: `slow_iteration.sidekiq` via `bundle exec sidekiq` + iterable test job
- [x] `bundle exec rake test` (full suite, requires dedicated Redis / no competing Sidekiq)
