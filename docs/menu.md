# Sidekiq public API documentation

Sidekiq provides a number of public APIs for various functionality.

1. Middleware
2. Lifecycle Events
3. Data API
4. Components

## Middleware

Middleware run around the the client-side push and the server-side execution of jobs. This allows plugins which mutate job data or provide additional functionality during the executiong of specific jobs.

## Lifecycle Events

With lifecycle events, Sidekiq plugins can register a callback upon `startup`, `quiet` or `shutdown`.
This is useful for starting and stopping your own Threads or services within the Sidekiq process.

## Data API

The code in `sidekiq/api` provides a Ruby facade on top of Sidekiq's persistent data within Redis.
It contains many classes and methods for discovering, searching and iterating through the real-time job data within the queues and sets inside Redis.
This API powers the Sidekiq::Web UI.