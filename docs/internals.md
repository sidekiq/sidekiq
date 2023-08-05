# Sidekiq Internals

## Quick Jump
<!--toc:start-->
- [Sidekiq Internals](#sidekiq-internals)
  - [Table of Contents](#table-of-contents)
  - [bundle exec sidekiq](#bundle-exec-sidekiq)
  - [embedded](#embedded)
<!--toc:end-->



This document explains Sidekiq 7.0 internal code structure and implementation.

## `bundle exec sidekiq`

When you start a Sidekiq instance using `bundle exec sidekiq`, execution starts in `bin/sidekiq`.
This executable creates an instance of `Sidekiq::CLI` and runs it.

`Sidekiq::CLI` has three main responsibilities:

1. parse any command line args, ENV args or configuration file (e.g. `config/sidekiq.yml`), put that data into a `Sidekiq::Config` instance at `Sidekiq.default_configuration`
2. boot any Rails application or script specified via `-r`
3. trap any process signals and handle them (TERM, TTIN, TSTP)

Once booted, Sidekiq::CLI creates an instance of `Sidekiq::Launcher` for the `Sidekiq::Config` instance.

`Sidekiq::Launcher` has several responsibilities:

1. provide a heartbeat thread which informs the Web UI that we are alive and well
2. provide a scheduler thread which enqueues jobs which have reached their scheduled time and can be enqueued for immediate execution
3. create a `Sidekiq::Manager` for each configured `Sidekiq::Capsule`.

`Sidekiq::Capsule` represents resources necessary to process one or more queues. The user
configures a set of queues along with the specified concurrency. Each capsule will have a `Sidekiq::BasicFetch` instance.

`Sidekiq::Manager` manages the resources for a given `Sidekiq::Capsule`. It creates and starts N `Sidekiq::Processor` instances. It listens for any errors reported by a Processor thread. If a Processor reports an error, the Manager will discard that Processor and spin up a new one, to ensure there is no cross-contamination when executing future jobs. Finally, the Manager is responsible for cleanly shutting down all the Processor threads at shutdown.

Each `Sidekiq::Processor` instance is a separate thread. A Processor thread knows how to fetch a job from Redis, run any configured middleware for its Capsule and then execute the job. A special
component in the execution path, `Sidekiq::JobRetry`, catches any Exception from this block and moves the job plus the error information into the `retry` set in Redis for future retries if necessary.

## embedded

Sidekiq 7.0's new embedded mode of operation allows the user to run a Sidekiq instance within an arbitrary Ruby process. `Sidekiq::Embedded` takes the place of Sidekiq::CLI and allows the user to create, configure and manage their own `Sidekiq::Launcher` instance.

As noted above, when embedded, Sidekiq expects the process starter to take `Sidekiq::CLI`'s responsibilities.
For instance, within `puma` we expect puma to parse command line arguments, boot the app, handle signals, etc.
Your Ruby code creates and configures the embedded Sidekiq instance.

The standard Ruby runtime does not scale well with lots of Threads so embedded mode defaults to a concurrency of only 2 as it needs to share that limited pool of Threads with the process owner, often a library like `puma` running CPU-hungry Rails apps. If your puma thread count is 5, I would not touch Sidekiq's default concurrency of 2. Keep watch on your CPU usage and tune puma's `threads X, Y` value or Sidekiq's `config.concurrency = N` so that your Ruby processes aren't maxxed out of CPU. I would never recommend more than 10 threads executing application code per core unless you've specifically tested and know your app to be CPU-light.

> RULE OF THUMB: **if you are using embedded mode, you should be monitoring the CPU usage of that process!**

Note the other Threads enumerated above. The concurrency value controls how many Processor threads will be started but there are also separate threads for heartbeat, scheduler, and other internal services. These threads are relatively CPU-light but they still need regular, predictable access to the CPU for their own work.
