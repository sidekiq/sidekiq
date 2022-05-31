# Sidekiq 7.0 Components

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

The problem is that this pattern implies a global, mutable singleton.
It does not work with Ractors. It does not allow multiple instances in one process.
It does not allow embedding within another Ruby process (e.g. puma).
Today the only supported Sidekiq deployment pattern is running `bundle exec sidekiq`.

# The Solution

Sidekiq 7.0 aims to refactor Sidekiq internals to allow more flexibility in how
Sidekiq can be used.

## Sidekiq::Config

`Sidekiq::Config` represents the configuration for an instance of Sidekiq. Sidekiq::CLI
creates a `Sidekiq::Config` instance and mutates it according to the command line parameters
and the data in `config/sidekiq.yml`.

`Sidekiq::Launcher` is the top-level component which takes a `Sidekiq::Config` and creates the
tree of runtime components. Once passed to Launcher, the Config is frozen and immutable.

Every internal component of Sidekiq takes a `Sidekiq::Config` instance and uses it. The Config
holds previously "global" state like the connection pool, error handlers, lifecycle callbacks, etc. 

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
`config.xyz`.