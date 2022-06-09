# Reducing Global API usage in Sidekiq 7.0

In Sidekiq 6.x, we rely heavily on top-level APIs and options within the Sidekiq module itself. APIs like `Sidekiq.options` are used everywhere to pull dynamic configuration.
This makes Sidekiq incompatible with Ractors or embedding within other processes.

# Implicit Configuration

Since the beginning, Sidekiq has used a global singleton for configuration. This was
accessed via `Sidekiq.configure_{client,server} do |config|`. You don't create a Sidekiq
instance but one is implicitly provided for you to configure.

Moving forward we want move to a more explicit `Sidekiq::Config` API which encapsulates this data. We provide backwards compatibility for the most widely used patterns but a few things
will need to change:

```ruby
# In 6.x `config` points to the Sidekiq module directly.
# In 7.x it will be an instance of Sidekiq::Config.
Sidekiq.configure_server do |config|
  config.options[:concurrency] = 5 # Sidekiq.options is deprecated
  config.concurrency = 5           # new
end
```

To be clear: `Sidekiq.configure_{client,server}` will remain supported for the
foreseeable future. How Sidekiq works by default will remain very, very similar but these
small tweaks will allow a new mode of operation for Sidekiq and unlock a few, new usecases... 

# Explicit Configuration

Sidekiq 7.0 is expected to provide a new Ruby API for configuring and launching Sidekiq
instances within an existing Ruby process. For instance, you could launch Sidekiq
within a Puma process if you wanted to minimize the memory required for two separate
processes (of course, the normal GIL caveats apply: one core can only handle so many requests and jobs). I call this **embedded mode**.

Another idea: you could start a second, small instance within your main Sidekiq process
to limit concurrent job execution for a special queue. Maybe those jobs aren't thread-safe
or use a 3rd party service which imposes a very limited access policy.

```ruby
cfg = Sidekiq::Config.new
cfg.concurrency = 1
cfg.queues = %w[limited]

launcher = Sidekiq::Launcher.new(cfg) # cfg is now frozen!
launcher.start
# processing jobs!
launcher.stop
```

## Notes

- Every `Sidekiq::Launcher` instance is considered a separate "process" in the Web UI. You
  could launch N instances within one Ruby process and the Web UI will show N "processes". Why you'd want to do this, I don't know. "Just because you can doesn't mean you should" remains true.
- How this configuration refactoring affects Sidekiq Pro and Sidekiq Enterprise remains to be
  seen. Existing functionality will remain supported and any breakage will be
  documented in the major version upgrade notes.