# Upgrading to Sidekiq Pro 2.0

Sidekiq Pro 2.0 removes deprecated APIs, changes the batch data format and
how features are activated. To upgrade cleanly:

## Batches

* Batch 2.x BIDs are 14 character URL-safe Base64-encoded strings, e.g.
  "vTF1-9QvLPnREQ".
  Batch 1.x BIDs were 16 character hex-encoded strings, e.g. "4a3fc67d30370edf".
* In 1.x, batch data expired after 72 hours.  In 2.x, all data in Redis
  for a batch is removed once the batch has run any success callbacks.
* Because of the former point, batch expiry is no longer a concern.
  Batch expiry is hardcoded to 30 days and is no longer user-tunable.
* Sidekiq::Batch#notify was removed.  This API was a very thin layer
  on top of the more flexible `Sidekiq::Batch#on` API that everyone
  should be using.
* You must require `sidekiq/notifications` if you want to use the
  pre-defined notification schemes.

## Reliability

* Reliable fetch is now activated without a require:
```ruby
Sidekiq.configure_server do |config|
  config.reliable_fetch!
end
* Reliable push is now activated without a require:
```ruby
Sidekiq::Client.reliable_push!
```
