# Middleware Changes in Sidekiq 7.0

With the internal refactoring coming in Sidekiq 7.0 it is necessary
to make minor changes to the Middleware API.

> tl;dr - middleware should now include Sidekiq::ClientMiddleware or Sidekiq::ServerMiddleware.

Currently the middleware API looks like this:

## Existing Client API

Client middleware is run when pushing a job to Redis.

```ruby
class Client
  def initialize(optional_args)
    @args = optional_args
  end
  def call(worker, job, queue, redis_pool)
    yield
  end
end

Sidekiq.configure_client do |config|
  config.client_middleware do |chain|
    chain.add Client, optional_args
  end
end
```

## Server

Server middleware is run around job execution.

```ruby
class Server
  def initialize(optional_args)
    @args = optional_args
  end
  def call(worker, job, queue)
    Sidekiq.redis {|c| c.do_something }
    Sidekiq.logger.info { "Some message" }
    yield
  end
end

Sidekiq.configure_server do |config|
  config.server_middleware do |chain|
    chain.add Server, optional_args
  end
end
```

## Updated API

The updated middleware API requires the middleware class to include
a helper module.

```ruby
class Client
  include Sidekiq::ClientMiddleware

  def initialize(optional_args)
    @args = optional_args
  end
  # @see https://github.com/sidekiq/sidekiq/wiki/Middleware
  def call(job_class_or_string, job, queue, redis_pool)
    yield
  end
end
```

```ruby
class Server
  include Sidekiq::ServerMiddleware

  def initialize(optional_args)
    @args = optional_args
  end
  
  # @see https://github.com/sidekiq/sidekiq/wiki/Middleware
  def call(job_instance, job_payload, queue)
    # note we no longer need to use the global Sidekiq module
    # to access Redis and the logger
    redis {|c| c.do_something }
    logger.info { "Some message" }
    yield
  end
end
```
