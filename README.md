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
 and how I was able to shrink a Carbon Five client's processing farm
from 9 machines to 1 machine.


Requirements
-----------------

I test on Ruby 1.9.3 and JRuby 1.6.5 in 1.9 mode.  Other versions/VMs are
untested.


Installation
-----------------

   gem install sidekiq


Usage
-----------------

See `sidekiq -h` for usage details.


Client
-----------------

The Sidekiq client can be used to enqueue messages for processing:

    Sidekiq::Client.push('some_queue', 'class' => SomeWorker, 'args' => ['bob', 2, foo: 'bar'])


How it works
-----------------

Sidekiq assumes you are running a Rails 3 application.  Each message has a format like:

    { class: 'SomeWorker', args: ['bob', 2, {foo: 'bar'}] }

Sidekiq will instantiate a new instance of SomeWorker and call perform
with args splatted:

    class SomeWorker
      def perform(name, count, options)
      end
    end

This is the main API difference between Resque and Sidekiq: the perform
method is an *instance* method, not a *class* method.  This difference
is here because you, as a developer, must make your workers threadsafe.
I don't want to call a Resque worker which might be non-threadsafe.


Connections
-----------------

If your workers are connecting to mongo, memcached, redis, cassandra,
etc you might want to set up a shared connection pool that all workers
can use so you aren't opening a new connection for every message
processed.  Sidekiq contains a connection pool API which you can use in your code to
ensure safe, simple access to shared IO connections.  Please see the
[connection\_pool gem](https://github.com/mperham/connection_pool) for more information.
Your worker would do something like this:

    class Worker
      REDIS_POOL = ConnectionPool.new(:size => 10, :timeout => 3) { Redis.new }
      def perform(args)
        REDIS_POOL.with_connection do |redis|
          redis.lsize(:foo)
        end
      end
    end

This ensures that if you have a concurrency setting of 50, you'll still only
have a maximum of 10 connections open to Redis.


Error Handling
-----------------

Sidekiq has built-in support for Airbrake.  If a worker raises an
exception, Sidekiq will optionally send that error with the message
context to Airbrake, log the error and then replace the worker with a
fresh worker.  Just make sure you have Airbrake configured in your Rails
app.


Author
-----------------

Mike Perham, [@mperham](https://twitter.com/mperham), [http://mikeperham.com](http://mikeperham.com)

If your company uses and enjoys sidekiq, click below to support my
open source efforts.  I spend hundreds of hours of my spare time working
on projects like this.

<a href='http://www.pledgie.com/campaigns/16623'><img alt='Click here to lend your support to Open Source and make a donation at www.pledgie.com !' src='http://www.pledgie.com/campaigns/16623.png?skin_name=chrome' border='0' /></a>
