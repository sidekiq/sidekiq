# Add instrumentation handlers for operational warnings (#6461)

Fixes #6461

**Draft** — addressing review feedback before requesting re-review.

Initial design proposal for official Sidekiq instrumentation. Operational warnings that were previously **log-only** can now be subscribed to by apps and monitoring gems without monkeypatching Sidekiq internals. Existing log output is unchanged — instrumentation is additive.

Core instrumentation is **standalone** (no ActiveSupport dependency). When Sidekiq runs inside Rails, events are optionally forwarded to `ActiveSupport::Notifications` via a thin bridge in the Rails layer (`Sidekiq::Rails::Instrumentation::ActiveSupportBridge`).

## Motivation

Sidekiq already exposes hooks for **errors**:

- `config.error_handlers` — exceptions during job processing
- `config.death_handlers` — jobs that exhausted retries

Operational **warnings** (slow Redis RTT, slow iterable iterations, Redis misconfiguration, forced shutdown, Redis recovery) were only written to the log. Instrumentation gems often patch `Sidekiq::Processor`, middleware, or other internals — fragile and hard to maintain.

This PR adds a first-class subscription API, similar to `error_handlers`, so apps and gems can react to warnings without patching Sidekiq. Sidekiq Pro and Enterprise can publish additional events through the same API.

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

- `lib/sidekiq/instrumentation.rb` — event name constants
- `lib/sidekiq/config.rb` — `instrumentation_handlers`, `#instrument`
- `lib/sidekiq/component.rb` — `#instrument` delegate

Rails integration (loaded only when Rails is present):

- `lib/sidekiq/rails/instrumentation.rb` — `ActiveSupportBridge`
- `lib/sidekiq/rails.rb` — registers bridge on server boot

No `activesupport` dependency in the gemspec.

## API stability

Event names and payload keys in `Sidekiq::Instrumentation` are intended to be a supported, long-term contract once merged. New payload keys may be added in the future; existing keys should remain stable. Open to starting with fewer events in v1 if maintainers prefer a smaller surface.

## Handler execution

Handlers run synchronously on the calling thread, matching `error_handlers`. A slow handler can add latency on the instrumented code paths (operational warnings, not the per-job hot loop). Handler failures are isolated and logged so they do not interrupt Sidekiq processing.

## API

### Register handlers (plain Ruby / any app)

Handlers are registered on the **server** config (events are published from Sidekiq worker processes):

```ruby
Sidekiq.configure_server do |config|
  config.instrumentation_handlers << ->(event, payload, cfg) do
    puts "[sidekiq] #{event} #{payload.inspect}"
  end
end
```

**Handler signature:** `(event, payload, config)`

| Argument  | Type   | Description                                |
|-----------|--------|--------------------------------------------|
| `event`   | String | e.g. `"slow_rtt.sidekiq"`                  |
| `payload` | Hash   | Structured metadata (JSON-friendly values) |
| `config`  | Config | The `Sidekiq::Config` instance             |

Multiple handlers are supported. If one handler raises, Sidekiq logs the failure and continues with the remaining handlers (same isolation model as `error_handlers`).

```ruby
class MyInstrumentationHandler
  def call(event, payload, config)
    StatsD.increment("sidekiq.events", tags: ["event:#{event}"])
  end
end

Sidekiq.configure_server do |config|
  config.instrumentation_handlers << MyInstrumentationHandler.new
end
```

### Publish events (internal / extensions)

Sidekiq components call `instrument(event, payload)` via `Sidekiq::Component`. Pro/Ent can use the same API:

```ruby
# Example future usage in sidekiq-pro (not part of this PR)
instrument("super_fetch.reclaimed.sidekiq", { jid: "...", queue: "default" })
```

Event name constants live in `Sidekiq::Instrumentation`.

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

  # MyAPM.increment("sidekiq.slow_rtt", tags: { identity: event.payload[:identity] })
end

at_exit { ActiveSupport::Notifications.unsubscribe(subscriber) }
```

Subscribe to all Sidekiq events:

```ruby
subscriber = ActiveSupport::Notifications.subscribe(/\.sidekiq\z/) do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  Rails.logger.info("[sidekiq] #{event.name} #{event.payload.inspect}")
end
```

Custom handler alongside the Rails bridge:

```ruby
Sidekiq.configure_server do |config|
  config.instrumentation_handlers << ->(event, payload, _cfg) do
    Lapsoss.report(event, context: payload) if event == Sidekiq::Instrumentation::HARD_SHUTDOWN
  end
end
```

Non-Rails apps: use `instrumentation_handlers` directly. No ActiveSupport bridge is registered unless you add one yourself.

## Published events (OSS)

Event names follow Rails convention: `name.sidekiq`.

| Constant | Event | When | Payload |
|----------|-------|------|---------|
| `SLOW_RTT` | `slow_rtt.sidekiq` | Last 5 Redis RTT samples all exceed 50,000µs | `{ readings:, threshold:, identity: }` |
| `SLOW_ITERATION` | `slow_iteration.sidekiq` | Iterable iteration exceeds `config[:timeout]` (default 25s) | `{ class:, jid:, duration:, timeout:, cursor: }` |
| `HARD_SHUTDOWN` | `hard_shutdown.sidekiq` | Shutdown timeout expires; busy threads force-killed | `{ thread_count:, job_count: }` |
| `REDIS_RECOVERED` | `redis_recovered.sidekiq` | Redis fetch failures recover | `{ downtime: }` (seconds) |

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

Boot-time configuration checks (e.g. Redis eviction policy) are intentionally excluded from v1 — they fire once per process and are better left as log warnings unless maintainers want them in a follow-up.

## Out of scope (this PR)

- Job perform timing (overlaps OSS metrics + Pro Statsd middleware)
- Job errors (already via `error_handlers` / `death_handlers`)
- Lifecycle callbacks as instrumentation (`config.on(:startup)` etc.)
- Boot-time configuration checks (e.g. Redis `maxmemory-policy` warning)

## Open questions for reviewers

1. Handler signature `(event, payload, config)` — mirrors `error_handlers`; alternatives welcome
2. Event naming — `.sidekiq` suffix matches AS conventions
3. Payload shapes — flat and JSON-friendly; fields to add/remove?
4. Extension model — sufficient for Pro/Ent to publish via the same `instrument` API?
5. Block/timing form (`instrument("foo") { ... }`) — needed in v1 or later?

## Manual testing

Validated locally in both a non-Rails and a Rails environment.

### Non-Rails (standalone core)

From the repo root:

```bash
bundle exec irb -Ilib -r sidekiq
```

```ruby
cfg = Sidekiq.default_configuration
cfg.instrumentation_handlers.clear
cfg.instrumentation_handlers << ->(event, payload, _cfg) { puts "#{event} => #{payload.inspect}" }
cfg.instrument(Sidekiq::Instrumentation::SLOW_RTT, readings: [60_000], threshold: 50_000)
# => slow_rtt.sidekiq => {readings: [60000], threshold: 50000}
```

No ActiveSupport bridge is registered.

### Rails (in-repo `myapp`)

The sample app uses `gem "sidekiq", path: ".."`:

```bash
cd myapp
bundle exec sidekiq
```

**`slow_iteration.sidekiq`** — temporary test job with `sleep(6)` and `config[:timeout] = 5` in `Sidekiq.configure_server`, then:

```bash
bundle exec rails runner "SlowIterationTestJob.perform_async"
```

Confirm event + log warning in the Sidekiq process (~6s later). `rails runner` returns immediately; the job runs in the Sidekiq terminal.

## Test plan

- [x] `bundle exec ruby -Itest test/instrumentation_test.rb`
- [x] `bundle exec ruby -Itest test/rails_instrumentation_test.rb`
- [x] Manual smoke test (core, no Rails):

  ```ruby
  cfg = Sidekiq.default_configuration
  cfg.instrumentation_handlers.clear
  cfg.instrumentation_handlers << ->(event, payload, _cfg) { puts "#{event} => #{payload.inspect}" }
  cfg.instrument(Sidekiq::Instrumentation::SLOW_RTT, readings: [60_000], threshold: 50_000)
  # => slow_rtt.sidekiq => {readings: [60000], threshold: 50000}
  ```

- [x] Rails: subscribe to `slow_iteration.sidekiq`, run iterable job with `sleep(6)` and `config[:timeout] = 5`, confirm event + log warning
- [x] `bundle exec rake test` (full suite, requires Redis)
