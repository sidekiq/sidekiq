# Sidekiq 7.0 Capsules

Sidekiq 7.0 contains the largest internal refactoring since Sidekiq 4.0.
This refactoring is designed to improve deployment flexibility and allow
new use cases.

# The Problem

Before 7.0, Sidekiq used a large number of global methods on the Sidekiq module to access things
like the Redis connection pool, the logger, and process configuration, e.g.

```ruby
Sidekiq.logger.info "Hello world"
Sidekiq.redis {|c| c.sadd("some_set", "new_member") }
Sidekiq.configure_server {|config| config... }
```

The issue is that this pattern implies a global, mutable singleton.
It does not work with Ractors. It does not allow multiple instances in one process.
It does not allow embedding within another Ruby process (e.g. puma).
Today the only supported Sidekiq deployment pattern is running `bundle exec sidekiq`.

# The Solution

Sidekiq 7.0 aims to refactor Sidekiq internals to allow more flexibility in how
Sidekiq can be used.

## Sidekiq::Config

Before, all Sidekiq configuration went through the Sidekiq module and was stored in the top-level hash at `Sidekiq.options`.
Now Sidekiq::CLI creates a `Sidekiq::Config` object which holds the global configuration at, shockingly, `Sidekiq.global_configuration`.
This instance is now passed into `Sidekiq.configure_{client,server} do |config|`

## Sidekiq::Capsule

`Sidekiq::Capsule` represents the set of resources necessary to process a set of queues.
By default, Sidekiq::CLI creates one `Sidekiq::Capsule` instance and mutates it according to the command line parameters and the data in `config/sidekiq.yml`.

You create additional Capsules within your initializer, like so:

```ruby
Sidekiq.configure_server do |config|
  config.capsule("single-threaded") do |cap|
    cap.concurrency = 1
    cap.queues = %w[single]
  end
end
```

Capsules can have their own customized middleware chains but by default will inherit the global middleware configuration. Each Capsule will have its own Redis connection pool sized to the configured concurrency.

`Sidekiq::Launcher` is the top-level component which takes a `Sidekiq::Config` and launches the
tree of runtime components for each capsule. Once passed to Launcher, the global Config and each Capsule should be considered frozen and immutable.

Every internal component of Sidekiq takes a `Sidekiq::Capsule` instance and uses it. The Capsule
holds previously "global" state like the connection pool, error handlers, lifecycle callbacks, etc. 

There is still one iron-clad rule: **a Sidekiq process only executes jobs from one Redis instance**; all Capsules within a process must use the same Redis instance.
If you want to process jobs from two separate Redis instances, you need to start two separate Sidekiq processes.

## Use Cases

With Capsules, you can programmatically tune how a Sidekiq process handles specific queues. One
Capsule can use 1 thread to process jobs within a `thread_unsafe` queue while another Capsule uses
10 threads to process `default` jobs.

```ruby
# within your initializer
Sidekiq.configure_server do |config|
  config.capsule("unsafe") do |capsule|
    capsule.queues = %w(thread_unsafe)
    capsule.concurrency = 1
  end
end
```

The contents of `config/sidekiq.yml` configure the default capsule.

## Redis Pools

Before 7.0, the Sidekiq process would create a redis pool sized to `concurrency + 3`.
Now Sidekiq will create multiple Redis pools: a global pool of **five** connections available to global components, a pool of **concurrency** for the job processors within each Capsule.

So for a Sidekiq process with a default Capsule and a single threaded Capsule, you should have three Redis pools of size 5, 10 and 1.
Remember that connection pools are lazy so it won't create all those connections unless they are actively needed.

All Sidekiq components and add-ons should avoid using `Sidekiq.redis` or `Sidekiq.logger`.
Instead use the implicit `redis` or `logger` methods available on `Sidekiq::Component`, `Sidekiq::Capsule` or `Sidekiq::{Client,Server}Middleware`.

## Sidekiq::Component

`Sidekiq::Component` is a module which provides helpful methods based on a `config` reader:

```ruby
module Sidekiq::Component
  def config
    @config
  end

  def redis(&block)
    config.redis(&block)
  end

  def logger
    config.logger
  end

  def handle_exception(ex, ctx)
    # avoids calling `Sidekiq.error_handlers...`
    config.handle_exception(ex, ctx)
  end
end

class Sidekiq::Processor
  include Sidekiq::Component

  def initialize(capsule)
    @config = capsule
  end

  def ...
    # old
    Sidekiq.redis {|c| ... }
    Sidekiq.logger.info "Hello world!"

    # new
    redis {|c| ... }
    logger.info "Hello world!"
  rescue => ex
    handle_exception(ex, ...)
  end
end
```

Sidekiq::Capsule overrides Sidekiq::Config in order to provide Capsule-local resources so
you'll see places within Sidekiq where Capsule acts like a Config.

With this pattern, we greatly reduce the use of global APIs throughout Sidekiq internals.
Where before we'd call `Sidekiq.xyz`, we instead provide similar functionality like
`config.xyz`.
