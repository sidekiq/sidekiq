2.3.3
-----------

- Remove option to disable Rails hooks. [#401]
- Allow delay of any module class method

2.3.2
-----------

- Fix retry.  2.3.1 accidentally disabled it.

2.3.1
-----------

- Add Sidekiq::Client.push\_bulk for bulk adding of jobs to Redis.
  My own simple test case shows pushing 10,000 jobs goes from 5 sec to 1.5 sec.
- Add support for multiple processes per host to Capistrano recipe
- Re-enable Celluloid::Actor#defer to fix stack overflow issues [#398]

2.3.0
-----------

- Upgrade Celluloid to 0.12
- Upgrade Twitter Bootstrap to 2.1.0
- Rescue more Exceptions
- Change Job ID to be Hex, rather than Base64, for HTTP safety
- Use `Airbrake#notify_or_ignore`

2.2.1
-----------

- Add support for custom tabs to Sidekiq::Web [#346]
- Change capistrano recipe to run 'quiet' before deploy:update\_code so
  it is run upon both 'deploy' and 'deploy:migrations'. [#352]
- Rescue Exception rather than StandardError to catch and log any sort
  of Processor death.

2.2.0
-----------

- Roll back Celluloid optimizations in 2.1.0 which caused instability.
- Add extension to delay any arbitrary class method to Sidekiq.
  Previously this was limited to ActiveRecord classes.

```ruby
SomeClass.delay.class_method(1, 'mike', Date.today)
```

- Sidekiq::Client now generates and returns a random, 128-bit Job ID 'jid' which
  can be used to track the processing of a Job, e.g. for calling back to a webhook
  when a job is finished.

2.1.1
-----------

- Handle networking errors causing the scheduler thread to die [#309]
- Rework exception handling to log all Processor and actor death (#325, subelsky)
- Clone arguments when calling worker so modifications are discarded. (#265, hakanensari)

2.1.0
-----------

- Tune Celluloid to no longer run message processing within a Fiber.
  This gives us a full Thread stack and also lowers Sidekiq's memory
  usage.
- Add pagination within the Web UI [#253]
- Specify which Redis driver to use: *hiredis* or *ruby* (default)
- Remove FailureJobs and UniqueJobs, which were optional middleware
  that I don't want to support in core. [#302]

2.0.3
-----------
- Fix sidekiq-web's navbar on mobile devices and windows under 980px (ezkl)
- Fix Capistrano task for first deploys [#259]
- Worker subclasses now properly inherit sidekiq\_options set in
  their superclass [#221]
- Add random jitter to scheduler to spread polls across POLL\_INTERVAL
  window. [#247]
- Sidekiq has a new mailing list: sidekiq@librelist.org  See README.

2.0.2
-----------

- Fix "Retry Now" button on individual retry page. (ezkl)

2.0.1
-----------

- Add "Clear Workers" button to UI.  If you kill -9 Sidekiq, the workers
  set can fill up with stale entries.
- Update sidekiq/testing to support new scheduled jobs API:

   ```ruby
   require 'sidekiq/testing'
   DirectWorker.perform_in(10.seconds, 1, 2)
   assert_equal 1, DirectWorker.jobs.size
   assert_in_delta 10.seconds.from_now.to_f, DirectWorker.jobs.last['at'], 0.01
   ```

2.0.0
-----------

- **SCHEDULED JOBS**!

You can now use `perform_at` and `perform_in` to schedule jobs
to run at arbitrary points in the future, like so:

```ruby
  SomeWorker.perform_in(5.days, 'bob', 13)
  SomeWorker.perform_at(5.days.from_now, 'bob', 13)
```

It also works with the delay extensions:

```ruby
  UserMailer.delay_for(5.days).send_welcome_email(user.id)
```

The time is approximately when the job will be placed on the queue;
it is not guaranteed to run at precisely at that moment in time.

This functionality is meant for one-off, arbitrary jobs.  I still
recommend `whenever` or `clockwork` if you want cron-like,
recurring jobs.  See `examples/scheduling.rb`

I want to specially thank @yabawock for his work on sidekiq-scheduler.
His extension for Sidekiq 1.x filled an obvious functional gap that I now think is
useful enough to implement in Sidekiq proper.

- Fixed issues due to Redis 3.x API changes.  Sidekiq now requires
  the Redis 3.x client.
- Inline testing now round trips arguments through JSON to catch
  serialization issues (betelgeuse)

1.2.1
-----------

- Sidekiq::Worker now has access to Sidekiq's standard logger
- Fix issue with non-StandardErrors leading to Processor exhaustion
- Fix issue with Fetcher slowing Sidekiq shutdown
- Print backtraces for all threads upon TTIN signal [#183]
- Overhaul retries Web UI with new index page and bulk operations [#184]

1.2.0
-----------

- Full or partial error backtraces can optionally be stored as part of the retry
  for display in the web UI if you aren't using an error service. [#155]

```ruby
class Worker
  include Sidekiq::Worker
  sidekiq_options :backtrace => [true || 10]
end
```
- Add timeout option to kill a worker after N seconds (blackgold9)

```ruby
class HangingWorker
  include Sidekiq::Worker
  sidekiq_options :timeout => 600
  def perform
    # will be killed if it takes longer than 10 minutes
  end
end
```

- Fix delayed extensions not available in workers [#152]
- In test environments add the `#drain` class method to workers. This method
  executes all previously queued jobs. (panthomakos)
- Sidekiq workers can be run inline during tests, just `require 'sidekiq/testing/inline'` (panthomakos)
- Queues can now be deleted from the Sidekiq web UI [#154]
- Fix unnecessary shutdown delay due to Retry Poller [#174]

1.1.4
-----------

- Add 24 hr expiry for basic keys set in Redis, to avoid any possible leaking.
- Only register workers in Redis while working, to avoid lingering
  workers [#156]
- Speed up shutdown significantly.

1.1.3
-----------

- Better network error handling when fetching jobs from Redis.
  Sidekiq will retry once per second until it can re-establish
  a connection. (ryanlecompte)
- capistrano recipe now uses `bundle_cmd` if set [#147]
- handle multi\_json API changes (sferik)

1.1.2
-----------

- Fix double restart with cap deploy [#137]

1.1.1
-----------

- Set procline for easy monitoring of Sidekiq status via "ps aux"
- Fix race condition on shutdown [#134]
- Fix hang with cap sidekiq:start [#131]

1.1.0
-----------

- The Sidekiq license has switched from GPLv3 to LGPLv3!
- Sidekiq::Client.push now returns whether the actual Redis
  operation succeeded or not. [#123]
- Remove UniqueJobs from the default middleware chain.  Its
  functionality, while useful, is unexpected for new Sidekiq
  users.  You can re-enable it with the following config.
  Read #119 for more discussion.

```ruby
Sidekiq.configure_client do |config|
  require 'sidekiq/middleware/client/unique_jobs'
  config.client_middleware do |chain|
    chain.add Sidekiq::Middleware::Client::UniqueJobs
  end
end
Sidekiq.configure_server do |config|
  require 'sidekiq/middleware/server/unique_jobs'
  config.server_middleware do |chain|
    chain.add Sidekiq::Middleware::Server::UniqueJobs
  end
end
```

1.0.0
-----------

Thanks to all Sidekiq users and contributors for helping me
get to this big milestone!

- Default concurrency on client-side to 5, not 25 so we don't
  create as many unused Redis connections, same as ActiveRecord's
  default pool size.
- Ensure redis= is given a Hash or ConnectionPool.

0.11.2
-----------

- Implement "safe shutdown".  The messages for any workers that
  are still busy when we hit the TERM timeout will be requeued in
  Redis so the messages are not lost when the Sidekiq process exits.
  [#110]
- Work around Celluloid's small 4kb stack limit [#115]
- Add support for a custom Capistrano role to limit Sidekiq to
  a set of machines. [#113]

0.11.1
-----------

- Fix fetch breaking retry when used with Redis namespaces. [#109]
- Redis connection now just a plain ConnectionPool, not CP::Wrapper.
- Capistrano initial deploy fix [#106]
- Re-implemented weighted queues support (ryanlecompte)

0.11.0
-----------

- Client-side API changes, added sidekiq\_options for Sidekiq::Worker.
  As a side effect of this change, the client API works on Ruby 1.8.
  It's not officially supported but should work [#103]
- NO POLL!  Sidekiq no longer polls Redis, leading to lower network
  utilization and lower latency for message processing.
- Add --version CLI option

0.10.1
-----------

- Add details page for jobs in retry queue (jcoene)
- Display relative timestamps in web interface (jcoene)
- Capistrano fixes (hinrik, bensie)

0.10.0
-----------

- Reworked capistrano recipe to make it more fault-tolerant [#94].
- Automatic failure retry!  Sidekiq will now save failed messages
  and retry them, with an exponential backoff, over about 20 days.
  Did a message fail to process?  Just deploy a bug fix in the next
  few days and Sidekiq will retry the message eventually.

0.9.1
-----------

- Fix missed deprecations, poor method name in web UI

0.9.0
-----------

- Add -t option to configure the TERM shutdown timeout
- TERM shutdown timeout is now configurable, defaults to 5 seconds.
- USR1 signal now stops Sidekiq from accepting new work,
  capistrano sends USR1 at start of deploy and TERM at end of deploy
  giving workers the maximum amount of time to finish.
- New Sidekiq::Web rack application available
- Updated Sidekiq.redis API

0.8.0
-----------

- Remove :namespace and :server CLI options (mperham)
- Add ExceptionNotifier support (masterkain)
- Add capistrano support (mperham)
- Workers now log upon start and finish (mperham)
- Messages for terminated workers are now automatically requeued (mperham)
- Add support for Exceptional error reporting (bensie)

0.7.0
-----------

- Example chef recipe and monitrc script (jc00ke)
- Refactor global configuration into Sidekiq.configure\_server and
  Sidekiq.configure\_client blocks. (mperham)
- Add optional middleware FailureJobs which saves failed jobs to a
  'failed' queue (fbjork)
- Upon shutdown, workers are now terminated after 5 seconds.  This is to
  meet Heroku's hard limit of 10 seconds for a process to shutdown. (mperham)
- Refactor middleware API for simplicity, see sidekiq/middleware/chain. (mperham)
- Add `delay` extensions for ActionMailer and ActiveRecord. (mperham)
- Added config file support. See test/config.yml for an example file.  (jc00ke)
- Added pidfile for tools like monit (jc00ke)

0.6.0
-----------

- Resque-compatible processing stats in redis (mperham)
- Simple client testing support in sidekiq/testing (mperham)
- Plain old Ruby support via the -r cli flag (mperham)
- Refactored middleware support, introducing ability to add client-side middleware (ryanlecompte)
- Added middleware for ignoring duplicate jobs (ryanlecompte)
- Added middleware for displaying jobs in resque-web dashboard (maxjustus)
- Added redis namespacing support (maxjustus)

0.5.1
-----------

- Initial release!
