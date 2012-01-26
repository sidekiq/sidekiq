Sidekiq
==============

Simple, efficient message processing for Ruby.

Sidekiq aims to be a drop-in replacement for Resque.  It uses the exact same
message format as Resque so it can slowly replace an existing Resque processing farm.
You can have Sidekiq and Resque run side-by-side at the same time and
use the Resque client to enqueue messages in Redis to be processed by Sidekiq.

Sidekiq is different from Resque in how it processes messages: it
processes many messages concurrently per process.  Resque only processes
one message at a time per process so it is far less memory efficient.
You'll find that you might need 50 200MB resque processes to peg your CPU
whereas one 300MB Sidekiq process will peg the same CPU and perform the
same amount of work.  Please see [my blog post on Resque's memory
efficiency](http://blog.carbonfive.com/2011/09/16/improving-resques-memory-efficiency/)
 and how I was able to shrink a Carbon Five client's resque processing farm
from 9 machines to 1 machine.


Requirements
-----------------

I test on Ruby 1.9.3 and JRuby 1.6.5 in 1.9 mode.  Other versions/VMs are
untested.


Installation
-----------------

   gem install sidekiq


Getting Started
-----------------

See the [sidekiq home page](http://mperham.github.com/sidekiq) for the simple 4-step process.


More Information
-----------------

Please see the [sidekiq wiki](https://github.com/mperham/sidekiq/wiki) for more information.


License
-----------------

sidekiq is GPLv3 licensed for **non-commercial use only**.  For a commercial
license, you must give $50 to my [Pledgie campaign](http://www.pledgie.com/campaigns/16623).
Considering the hundreds of hours I've spent writing OSS, I hope you
think this is a reasonable price.  BTW, the commercial license is in
COMM-LICENSE and is the [Sencha commercial license v1.10](http://www.sencha.com/legal/sencha-commercial-software-license-agreement/) with the Support (section 11) terms removed.

<a href='http://www.pledgie.com/campaigns/16623'><img alt='Click here to lend your support to Open Source and make a donation at www.pledgie.com !' src='http://www.pledgie.com/campaigns/16623.png?skin_name=chrome' border='0' /></a>

Author
-----------------

Mike Perham, [@mperham](https://twitter.com/mperham), [http://mikeperham.com](http://mikeperham.com)

