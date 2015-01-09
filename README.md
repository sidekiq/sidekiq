Sidekiq
==============

[![Gem Version](https://badge.fury.io/rb/sidekiq.png)](https://rubygems.org/gems/sidekiq) [![Code Climate](https://codeclimate.com/github/mperham/sidekiq.png)](https://codeclimate.com/github/mperham/sidekiq) [![Build Status](https://travis-ci.org/mperham/sidekiq.png)](https://travis-ci.org/mperham/sidekiq) [![Coverage Status](https://coveralls.io/repos/mperham/sidekiq/badge.png?branch=master)](https://coveralls.io/r/mperham/sidekiq)


Simple, efficient background processing for Ruby.

Sidekiq uses threads to handle many jobs at the same time in the
same process.  It does not require Rails but will integrate tightly with
Rails 3/4 to make background processing dead simple.

Sidekiq is compatible with Resque.  It uses the exact same
message format as Resque so it can integrate into an existing Resque processing farm.
You can have Sidekiq and Resque run side-by-side at the same time and
use the Resque client to enqueue jobs in Redis to be processed by Sidekiq.

At the same time, Sidekiq uses multithreading so it is much more memory efficient than
Resque (which forks a new process for every job).  You'll find that you might need
10 200MB resque processes to peg your CPU whereas one 300MB Sidekiq process will peg
the same CPU and perform the same amount of work.


Requirements
-----------------

I test with the latest MRI (2.2, 2.1 and 2.0) and JRuby versions (1.7).  Other versions/VMs
are untested but might work fine.  MRI 1.9 is no longer supported.

All Rails releases starting from 3.2 are officially supported.

Redis 2.4 or greater is required.


Installation
-----------------

    gem install sidekiq


Getting Started
-----------------

See the [sidekiq home page](http://sidekiq.org) for the simple 3-step process.
You can watch [Railscast #366](http://railscasts.com/episodes/366-sidekiq) to see Sidekiq in action.  If you do everything right, you should see this: 

![Web UI](https://github.com/mperham/sidekiq/raw/master/examples/web-ui.png)


Want to Upgrade?
-------------------

I also sell Sidekiq Pro, an extension to Sidekiq which provides more
features, a commercial-friendly license and allows you to support high
quality open source development all at the same time.  Please see the
[Sidekiq Pro](http://sidekiq.org/pro) homepage for more detail.


More Information
-----------------

Please see the [sidekiq wiki](https://github.com/mperham/sidekiq/wiki) for the official documentation.
[#sidekiq on irc.freenode.net](irc://irc.freenode.net/#sidekiq) is dedicated to this project,
but bug reports or feature requests suggestions should still go through [issues on Github](https://github.com/mperham/sidekiq/issues).  Release announcements are made to the [@sidekiq](https://twitter.com/sidekiq) Twitter account.

You may also find useful a [Google Group](https://groups.google.com/forum/#!forum/sidekiq) dedicated to Sidekiq discussion and [a Sidekiq tag](https://stackoverflow.com/questions/tagged/sidekiq) on Stack Overflow.


Problems?
-----------------

**Please do not directly email any Sidekiq committers with questions or problems.**  A community is best served when discussions are held in public.

If you have a problem, please review the [FAQ](https://github.com/mperham/sidekiq/wiki/FAQ) and [Troubleshooting](https://github.com/mperham/sidekiq/wiki/Problems-and-Troubleshooting) wiki pages. Searching the issues for your problem is also a good idea.  If that doesn't help, feel free to email the Sidekiq mailing list or open a new issue.
The mailing list is the preferred place to ask questions on usage. If you are encountering what you think is a bug, please open an issue.


Thanks
-----------------

Sidekiq stays fast by using the [JProfiler java profiler](http://www.ej-technologies.com/products/jprofiler/overview.html) to find and fix
performance problems on JRuby.  Unfortunately MRI does not have good profile tooling.


License
-----------------

Please see [LICENSE](https://github.com/mperham/sidekiq/blob/master/LICENSE) for licensing details.


Author
-----------------

Mike Perham, [@mperham](https://twitter.com/mperham) / [@sidekiq](https://twitter.com/sidekiq), [http://www.mikeperham.com](http://www.mikeperham.com) / [http://www.contribsys.com](http://www.contribsys.com)
