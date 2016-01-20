Sidekiq
==============

[![Gem Version](https://badge.fury.io/rb/sidekiq.svg)](https://rubygems.org/gems/sidekiq)
[![Code Climate](https://codeclimate.com/github/mperham/sidekiq.svg)](https://codeclimate.com/github/mperham/sidekiq)
[![Build Status](https://travis-ci.org/mperham/sidekiq.svg)](https://travis-ci.org/mperham/sidekiq)
[![Gitter Chat](https://badges.gitter.im/mperham/sidekiq.svg)](https://gitter.im/mperham/sidekiq)


Simple, efficient background processing for Ruby.

Sidekiq uses threads to handle many jobs at the same time in the
same process.  It does not require Rails but will integrate tightly with
Rails 3/4 to make background processing dead simple.

Sidekiq is compatible with Resque.  It uses the exact same
message format as Resque so it can integrate into an existing Resque processing farm.
You can have Sidekiq and Resque run side-by-side at the same time and
use the Resque client to enqueue jobs in Redis to be processed by Sidekiq.

Sidekiq is fast.

Version |	Latency | Garbage created for 10,000 jobs	| Time to process 100,000 jobs |	Throughput
-----------------|------|---------|---------|------------------------
Sidekiq 4.0.0    | 10ms	| 151 MB  | 22 sec  | **4500 jobs/sec**
Sidekiq 3.5.1    | 22ms	| 1257 MB | 125 sec | 800 jobs/sec
Resque 1.25.2    |  -	  | -       | 420 sec | 240 jobs/sec
DelayedJob 4.1.1 |  -   | -       | 465 sec | 215 jobs/sec


Requirements
-----------------

I test with the latest CRuby (2.2, 2.1 and 2.0) and JRuby versions (9k).  Other versions/VMs
are untested but might work fine.  CRuby 1.9 is not supported.

All Rails releases from 3.2 are officially supported.

Redis 2.8 or greater is required.  3.0.3+ is recommended for large
installations with thousands of worker threads.


Installation
-----------------

    gem install sidekiq


Getting Started
-----------------

See the [Getting Started wiki page](https://github.com/mperham/sidekiq/wiki/Getting-Started) and follow the simple setup process.
You can watch [Railscast #366](http://railscasts.com/episodes/366-sidekiq) to see Sidekiq in action.  If you do everything right, you should see this:

![Web UI](https://github.com/mperham/sidekiq/raw/master/examples/web-ui.png)


Want to Upgrade?
-------------------

I also sell Sidekiq Pro and Sidekiq Enterprise, extensions to Sidekiq which provide more
features, a commercial-friendly license and allow you to support high
quality open source development all at the same time.  Please see the
[Sidekiq](http://sidekiq.org/) homepage for more detail.


Problems?
-----------------

**Please do not directly email any Sidekiq committers with questions or problems.**  A community is best served when discussions are held in public.

Please see the [sidekiq wiki](https://github.com/mperham/sidekiq/wiki) for the official documentation.
[mperham/sidekiq on Gitter](https://gitter.im/mperham/sidekiq) is dedicated to this project,
but bug reports or feature requests suggestions should still go through [issues on Github](https://github.com/mperham/sidekiq/issues).  Release announcements are made to the [@sidekiq](https://twitter.com/sidekiq) Twitter account.  **No support via Twitter.**

Every Friday morning is Sidekiq happy hour: I video chat and answer questions.
See the [Sidekiq support page](http://sidekiq.org/support).

You may also find useful a [Reddit area](https://reddit.com/r/sidekiq) dedicated to Sidekiq discussion and [a Sidekiq tag](https://stackoverflow.com/questions/tagged/sidekiq) on Stack Overflow.

If you have a problem, please review the [FAQ](https://github.com/mperham/sidekiq/wiki/FAQ) and [Troubleshooting](https://github.com/mperham/sidekiq/wiki/Problems-and-Troubleshooting) wiki pages. Searching the issues for your problem is also a good idea.  If that doesn't help, feel free to email the Sidekiq mailing list, chat in Gitter, or open a new issue.  StackOverflow or Reddit is the preferred place to ask questions on usage. If you are encountering what you think is a bug, please open an issue.


Thanks
-----------------

Sidekiq stays fast by using the [JProfiler java profiler](http://www.ej-technologies.com/products/jprofiler/overview.html) to find and fix
performance problems on JRuby.  Unfortunately MRI does not have good multithreaded profiling tools.


License
-----------------

Please see [LICENSE](https://github.com/mperham/sidekiq/blob/master/LICENSE) for licensing details.


Author
-----------------

Mike Perham, [@mperham](https://twitter.com/mperham) / [@sidekiq](https://twitter.com/sidekiq), [http://www.mikeperham.com](http://www.mikeperham.com) / [http://www.contribsys.com](http://www.contribsys.com)
