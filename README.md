Sidekiq
==============

Simple, efficient message processing for Ruby.

Sidekiq uses threads to handle many messages at the same time in the
same process.  It integrates tightly with Rails 3 to make background
message processing dead simple.

Sidekiq is compatible with Resque.  It uses the exact same
message format as Resque so it can integrate into an existing Resque processing farm.
You can have Sidekiq and Resque run side-by-side at the same time and
use the Resque client to enqueue messages in Redis to be processed by Sidekiq.

At the same time, Sidekiq uses multithreading so it much more memory efficient than
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


Installation
-----------------

   gem install sidekiq


Getting Started
-----------------

See the [sidekiq home page](http://mperham.github.com/sidekiq) for the simple 4-step process.


More Information
-----------------

Please see the [sidekiq wiki](https://github.com/mperham/sidekiq/wiki) for more information.
[#sidekiq on irc.freenode.net](irc://irc.freenode.net/#sidekiq) is dedicated to this project,
but bug reports or feature requests suggestions should still go through [issues on Github](https://github.com/mperham/sidekiq/issues).


License
-----------------

Please see LICENSE for licensing details.

<a href='http://www.pledgie.com/campaigns/16623'><img alt='Click here to lend your support to Open Source and make a donation at www.pledgie.com !' src='http://www.pledgie.com/campaigns/16623.png?skin_name=chrome' border='0' /></a>

Author
-----------------

Mike Perham, [@mperham](https://twitter.com/mperham), [http://mikeperham.com](http://mikeperham.com)
