Sidekiq Pro Changelog
=======================

Please see http://sidekiq.org/pro for more details and how to buy.

1.1.0
-----------

- New `sidekiq/pro/reliable_push` which makes Sidekiq::Client resiliant
  to Redis network failures. [#793]
- Move `sidekiq/reliable_fetch` to `sidekiq/pro/reliable_fetch`


1.0.0
-----------

- Sidekiq Pro changelog moved to mperham/sidekiq for public visibility.
- Add new Rack endpoint for easy polling of batch status via JavaScript.  See `sidekiq/rack/batch_status`

0.9.3
-----------

- Fix bad /batches path in Web UI
- Fix Sinatra conflict with sidekiq-failures

0.9.2
-----------

- Fix issue with lifecycle notifications not firing.

0.9.1
-----------

- Update due to Sidekiq API changes.

0.9.0
-----------

- Rearchitect Sidekiq's Fetch code to support different fetch
strategies.  Add a ReliableFetch strategy which works with Redis'
RPOPLPUSH to ensure we don't lose messages, even when the Sidekiq
process crashes unexpectedly. [mperham/sidekiq#607]

0.8.2
-----------

- Reimplement existing notifications using batch on_complete events.

0.8.1
-----------

- Rejigger batch callback notifications.


0.8.0
-----------

- Add new Batch 'callback' notification support, for in-process
  notification.
- Symbolize option keys passed to Pony [mperham/sidekiq#603]
- Batch no longer requires the Web UI since Web UI usage is optional.
  You must require is manually in your Web process:

```ruby
require 'sidekiq/web'
require 'sidekiq/batch/web'
mount Sidekiq::Web => '/sidekiq'
```


0.7.1
-----------

- Worker instances can access the associated jid and bid via simple
  accessors.
- Batches can now be modified while being processed so, e.g. a batch
  job can add additional jobs to its own batch.

```ruby
def perform(...)
  batch = Sidekiq::Batch.new(bid) # instantiate batch associated with this job
  batch.jobs do
    SomeWorker.perform_async # add another job
  end
end
```

- Save error backtraces in batch's failure info for display in Web UI.
- Clean up email notification a bit.


0.7.0
-----------

- Add optional batch description
- Mutable batches.  Batches can now be modified to add additional jobs
  at runtime.  Example would be a batch job which needs to create more
  jobs based on the data it is processing.

```ruby
batch = Sidekiq::Batch.new(bid)
batch.jobs do
  # define more jobs here
end
```
- Fix issues with symbols vs strings in option hashes


0.6.1
-----------

- Webhook notification support


0.6
-----------

- Redis pubsub
- Email polish


0.5
-----------

- Batches
- Notifications
- Statsd middleware
