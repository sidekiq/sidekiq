Sidekiq
==============

[![Build Status](https://secure.travis-ci.org/mperham/sidekiq.png)](http://travis-ci.org/mperham/sidekiq)
[![Dependency Status](https://gemnasium.com/mperham/sidekiq.png)](https://gemnasium.com/mperham/sidekiq)

Simple, efficient message processing for Ruby.

Sidekiq uses threads to handle many messages at the same time in the
same process.  It does not require Rails but will integrate tightly with
Rails 3 to make background message processing dead simple.

Sidekiq is compatible with Resque.  It uses the exact same
message format as Resque so it can integrate into an existing Resque processing farm.
You can have Sidekiq and Resque run side-by-side at the same time and
use the Resque client to enqueue messages in Redis to be processed by Sidekiq.

At the same time, Sidekiq uses multithreading so it is much more memory efficient than
Resque (which forks a new process for every job).  You'll find that you might need
50 200MB resque processes to peg your CPU whereas one 300MB Sidekiq process will peg
the same CPU and perform the same amount of work.  Please see [my blog post on Resque's memory
efficiency](http://blog.carbonfive.com/2011/09/16/improving-resques-memory-efficiency/)
 and how I was able to shrink a Carbon Five client's resque processing farm
from 9 machines to 1 machine.


Requirements
-----------------

I test on Ruby 1.9.3 and JRuby 1.6.x in 1.9 mode.  Other versions/VMs are
untested but I will do my best to support them.  Ruby 1.8 is not supported.

Redis 2.0 or greater is required.


Installation
-----------------

    gem install sidekiq


Getting Started
-----------------

See the [sidekiq home page](http://mperham.github.com/sidekiq) for the simple 4-step process.
You can watch [Railscast #366](http://railscasts.com/episodes/366-sidekiq) to see Sidekiq in action.


More Information
-----------------

Please see the [sidekiq wiki](https://github.com/mperham/sidekiq/wiki) for more information.
[#sidekiq on irc.freenode.net](irc://irc.freenode.net/#sidekiq) is dedicated to this project,
but bug reports or feature requests suggestions should still go through [issues on Github](https://github.com/mperham/sidekiq/issues).

There's also a mailing list via [Librelist](http://librelist.org) that you can subscribe to by sending
and email to <sidekiq@librelist.org> with a greeting in the body. To unsubscribe, send an email to <sidekiq-unsubscribe@librelist.org> and that's it!
Once archiving begins, you'll be able to visit [the archives](http://librelist.com/browser/sidekiq/) to see past threads.


Problems?
-----------------

**Please do not directly email any Sidekiq committers with questions or problems.**  A community is best served when discussions are held in public.

If you have a problem, please review the [FAQ](/mperham/sidekiq/wiki/FAQ) and [Troubleshooting](/mperham/sidekiq/wiki/Problems-and-Troubleshooting) wiki pages. Searching the issues for your problem is also a good idea.  If that doesn't help, feel free to email the Sidekiq mailing list or open a new issue.
The mailing list is the preferred place to ask questions on usage. If you are encountering what you think is a bug, please open an issue.


License
-----------------

Please see LICENSE for licensing details.

<a href='http://www.pledgie.com/campaigns/16623'><img alt='Click here to lend your support to Open Source and make a donation at www.pledgie.com !' src='http://www.pledgie.com/campaigns/16623.png?skin_name=chrome' border='0' /></a>

Author
-----------------

Mike Perham, [@mperham](https://twitter.com/mperham), [http://mikeperham.com](http://mikeperham.com)
