2.11.1
-----------

- Fix timeout warning.
- Add Dutch web UI locale.

2.11.0
-----------

- Upgrade to Celluloid 0.13. [#834]
- Remove **timeout** support from `sidekiq_options`.  Ruby's timeout
  is inherently unsafe in a multi-threaded application and was causing
  stability problems for many.  See http://bit.ly/OtYpK
- Add Japanese locale for Web UI [#868]
- Fix a few issues with Web UI i18n.

2.10.1
-----------

- Remove need for the i18n gem. (brandonhilkert)
- Improve redis connection info logging on startup for debugging
purposes [#858]
- Revert sinatra/slim as runtime dependencies
- Add `find_job` method to sidekiq/api


2.10.0
-----------

- Refactor algorithm for putting scheduled jobs onto the queue [#843]
- Fix scheduler thread dying due to incorrect error handling [#839]
- Fix issue which left stale workers if Sidekiq wasn't shutdown while
quiet. [#840]
- I18n for web UI.  Please submit translations of `web/locales/en.yml` for
your own language. [#811]
- 'sinatra', 'slim' and 'i18n' are now gem dependencies for Sidekiq.


2.9.0
-----------

- Update 'sidekiq/testing' to work with any Sidekiq::Client call. It
  also serializes the arguments as using Redis would. [#713]
- Raise a Sidekiq::Shutdown error within workers which don't finish within the hard
  timeout.  This is to prevent unwanted database transaction commits. [#377]
- Lazy load Redis connection pool, you no longer need to specify
  anything in Passenger or Unicorn's after_fork callback [#794]
- Add optional Worker#retries_exhausted hook after max retries failed. [jkassemi, #780]
- Fix bug in pagination link to last page [pitr, #774]
- Upstart scripts for multiple Sidekiq instances [dariocravero, #763]
- Use select via pipes instead of poll to catch signals [mrnugget, #761]

2.8.0
-----------

- I18n support!  Sidekiq can optionally save and restore the Rails locale
  so it will be properly set when your jobs execute.  Just include
  `require 'sidekiq/middleware/i18n'` in your sidekiq initializer. [#750]
- Fix bug which could lose messages when using namespaces and the message
needs to be requeued in Redis. [#744]
- Refactor Redis namespace support [#747].  The redis namespace can no longer be
  passed via the config file, the only supported way is via Ruby in your
  initializer:

```ruby
sidekiq_redis = { :url => 'redis://localhost:3679', :namespace => 'foo' }
Sidekiq.configure_server { |config| config.redis = sidekiq_redis }
Sidekiq.configure_client { |config| config.redis = sidekiq_redis }
```

A warning is printed out to the log if a namespace is found in your sidekiq.yml.


2.7.5
-----------

- Capistrano no longer uses daemonization in order to work with JRuby [#719]
- Refactor signal handling to work on Ruby 2.0 [#728, #730]
- Fix dashboard refresh URL [#732]

2.7.4
-----------

- Fixed daemonization, was broken by some internal refactoring in 2.7.3 [#727]

2.7.3
-----------

- Real-time dashboard is now the default web page
- Make config file optional for capistrano
- Fix Retry All button in the Web UI

2.7.2
-----------

- Remove gem signing infrastructure.  It was causing Sidekiq to break
when used via git in Bundler.  This is why we can't have nice things. [#688]


2.7.1
-----------

- Fix issue with hard shutdown [#680]


2.7.0
-----------

- Add -d daemonize flag, capistrano recipe has been updated to use it [#662]
- Support profiling via `ruby-prof` with -p.  When Sidekiq is stopped
  via Ctrl-C, it will output `profile.html`.  You must add `gem 'ruby-prof'` to your Gemfile for it to work.
- Dynamically update Redis stats on dashboard [brandonhilkert]
- Add Sidekiq::Workers API giving programmatic access to the current
  set of active workers.

```
workers = Sidekiq::Workers.new
workers.size => 2
workers.each do |name, work|
  # name is a unique identifier per Processor instance
  # work is a Hash which looks like:
  # { 'queue' => name, 'run_at' => timestamp, 'payload' => msg }
end
```

- Allow environment-specific sections within the config file which
override the global values [dtaniwaki, #630]

```
---
:concurrency:  50
:verbose:      false
staging:
  :verbose:      true
  :concurrency:  5
```


2.6.5
-----------

- Several reliability fixes for job requeueing upon termination [apinstein, #622, #624]
- Fix typo in capistrano recipe
- Add `retry_queue` option so retries can be given lower priority [ryanlower, #620]

```ruby
sidekiq_options queue: 'high', retry_queue: 'low'
```

2.6.4
-----------

- Fix crash upon empty queue [#612]

2.6.3
-----------

- sidekiqctl exits with non-zero exit code upon error [jmazzi]
- better argument validation in Sidekiq::Client [karlfreeman]

2.6.2
-----------

- Add Dashboard beacon indicating when stats are updated. [brandonhilkert, #606]
- Revert issue with capistrano restart. [#598]

2.6.1
-----------

- Dashboard now live updates summary stats also. [brandonhilkert, #605]
- Add middleware chain APIs `insert_before` and `insert_after` for fine
  tuning the order of middleware. [jackrg, #595]

2.6.0
-----------

- Web UI much more mobile friendly now [brandonhilkert, #573]
- Enable live polling for every section in Web UI [brandonhilkert, #567]
- Add Stats API [brandonhilkert, #565]
- Add Stats::History API [brandonhilkert, #570]
- Add Dashboard to Web UI with live and historical stat graphs [brandonhilkert, #580]
- Add option to log output to a file, reopen log file on USR2 signal [mrnugget, #581]

2.5.4
-----------

- `Sidekiq::Client.push` now accepts the worker class as a string so the
  Sidekiq client does not have to load your worker classes at all.  [#524]
- `Sidekiq::Client.push_bulk` now works with inline testing.
- **Really** fix status icon in Web UI this time.
- Add "Delete All" and "Retry All" buttons to Retries in Web UI


2.5.3
-----------

- Small Web UI fixes
- Add `delay_until` so you can delay jobs until a specific timestamp:

```ruby
Auction.delay_until(@auction.ends_at).close(@auction.id)
```

This is identical to the existing Sidekiq::Worker method, `perform_at`.

2.5.2
-----------

- Remove asset pipeline from Web UI for much faster, simpler runtime.  [#499, #490, #481]
- Add -g option so the procline better identifies a Sidekiq process, defaults to File.basename(Rails.root). [#486]

    sidekiq 2.5.1 myapp [0 of 25 busy]

- Add splay to retry time so groups of failed jobs don't fire all at once. [#483]

2.5.1
-----------

- Fix issues with core\_ext

2.5.0
-----------

- REDESIGNED WEB UI! [unity, cavneb]
- Support Honeybadger for error delivery
- Inline testing runs the client middleware before executing jobs [#465]
- Web UI can now remove jobs from queue. [#466, dleung]
- Web UI can now show the full message, not just 100 chars [#464, dleung]
- Add APIs for manipulating the retry and job queues.  See sidekiq/api. [#457]


2.4.0
-----------

- ActionMailer.delay.method now only tries to deliver if method returns a valid message.
- Logging now uses "MSG-#{Job ID}", not a random msg ID
- Allow generic Redis provider as environment variable. [#443]
- Add ability to customize sidekiq\_options with delay calls [#450]

```ruby
Foo.delay(:retry => false).bar
Foo.delay(:retry => 10).bar
Foo.delay(:timeout => 10.seconds).bar
Foo.delay_for(5.minutes, :timeout => 10.seconds).bar
```

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
