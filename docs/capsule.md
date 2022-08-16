# Sidekiq 7.0 Capsules

Sidekiq 7.0 contains the largest internal refactoring since Sidekiq 4.0.
This refactoring is designed to improve deployment flexibility and allow
new use cases.

# The Problem

Sidekiq today uses a large number of class-level methods to access things
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

## Sidekiq::Capsule

`Sidekiq::Capsule` represents the set of resources necessary to process a set of queues.
By default, Sidekiq::CLI creates a `Sidekiq::Capsule` instance and mutates it according to the command line parameters and the data in `config/sidekiq.yml`.

`Sidekiq::Launcher` is the top-level component which takes a `Sidekiq::Capsule` and creates the
tree of runtime components. Once passed to Launcher, the Capsule is frozen and immutable.

Every internal component of Sidekiq takes a `Sidekiq::Capsule` instance and uses it. The Capsule
holds previously "global" state like the connection pool, error handlers, lifecycle callbacks, etc. 

There is still one iron-clad rule: **a Sidekiq process only executes jobs from one Redis instance** so
all Capsules within a process must use the same Redis instance. If you want to process jobs from
two separate Redis instances, you need to start two separate Sidekiq processes.

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

## Sidekiq::Component

`Sidekiq::Component` is a module which provides helpful methods based on a `capsule` reader:

```ruby
module Sidekiq::Component
  def capsule
    @capsule
  end

  def redis(&block)
    capsule.redis(&block)
  end

  def logger
    capsule.logger
  end

  def handle_exception(ex, ctx)
    # avoids calling `Sidekiq.error_handlers...`
    capsule.handle_exception(ex, ctx)
  end
end

class Sidekiq::Processor
  include Sidekiq::Component

  def initialize(config)
    @config = config
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

With this pattern, we greatly reduce the use of global APIs throughout Sidekiq internals.
Where beforefore we'd call `Sidekiq.xyz`, we instead provide similar functionality like
`capsule.xyz`.