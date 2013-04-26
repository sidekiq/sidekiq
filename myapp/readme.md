# Ruby 2.0 slowness with big concurrency

To reproduce:

Install redis locally and checkout the Sidekiq repo:

```
git clone git://github.com/mperham/sidekiq
cd sidekiq/myapp
bundle
```

Load lots of jobs into Redis, you can edit Rakefile to change the job
   count:

```
> time bundle exec rake load_jobs
2013-04-26T15:32:37Z 66670 TID-ov6pgqt3k INFO: Sidekiq client using redis://localhost:6379/0 with options {:size=>2, :namespace=>"foo"}

real	0m49.206s
user	0m45.037s
sys	0m3.558s
```

Start Sidekiq with 200 worker threads to process those jobs.  You will need to kill Sidekiq with Ctrl-C as soon as log messages stop flying by.

```
> time bundle exec sidekiq -c 200
...
2013-04-26T15:46:25Z 67059 TID-ovwfo7krk EmptyWorker JID-cce0eed5ea7281b720841ecc INFO: done: 0.224 sec
2013-04-26T15:46:25Z 67059 TID-ovwfojqdg EmptyWorker JID-850c242ec75de77400838fa9 INFO: done: 0.231 sec
2013-04-26T15:46:25Z 67059 TID-ovwfo6u94 EmptyWorker JID-fd2422116a771dc67a848489 INFO: done: 0.223 sec
2013-04-26T15:46:25Z 67059 TID-ovwfo94ag EmptyWorker JID-45ecb59a43e62ebb574ee0da INFO: done: 0.223 sec
2013-04-26T15:46:25Z 67059 TID-ovwfonv7s EmptyWorker JID-c7beabde4c0141b0669c4baf INFO: done: 0.221 sec
^C2013-04-26T15:46:27Z 67059 TID-ovwfalyvw INFO: Shutting down
2013-04-26T15:46:27Z 67059 TID-ovwfefrzw INFO: Shutting down 200 quiet workers

real	3m37.921s
user	3m3.110s
sys	1m4.783s
> ruby -v
ruby 1.9.3p374 (2013-01-15 revision 38858) [x86_64-darwin12.3.0]
```

Now try with various Rubies to see how your choice in VM performs.

```
2013-04-26T15:57:04Z 67357 TID-ow0muevo8 EmptyWorker JID-cb03f00310af3590009b19fe INFO: done: 0.189 sec
2013-04-26T15:57:04Z 67357 TID-ow0muqgxc EmptyWorker JID-89710c72bf4a343834833bc4 INFO: done: 0.19 sec
2013-04-26T15:57:04Z 67357 TID-ow0ms6rc4 EmptyWorker JID-bb358d8d8f02af9734b8a3ff INFO: done: 0.186 sec
2013-04-26T15:57:04Z 67357 TID-ow0mwn908 EmptyWorker JID-7c032c55e6ab9a63dc31f175 INFO: done: 0.188 sec
2013-04-26T15:57:04Z 67357 TID-ow0mv6m80 EmptyWorker JID-73dc04f9e431ebf433707d02 INFO: done: 0.188 sec
^C2013-04-26T15:57:11Z 67357 TID-ow0m8kxh4 INFO: Shutting down
2013-04-26T15:57:11Z 67357 TID-ow0mwqr20 INFO: Shutting down 200 quiet workers

real	5m55.033s
user	5m6.156s
sys	1m4.886s
> ruby -v
ruby 2.0.0p0 (2013-02-24 revision 39474) [x86_64-darwin12.3.0]
```
