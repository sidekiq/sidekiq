This is a "service" directory for sidekiq. You should probably modify
the relevant paths in the run script, and the log/run script, if
necessary. It assumes a "sidekiq" user is created that will run the
sidekiq process. To supervise under runit, link this directory to the
runsvdir for your system (e.g., `/etc/service` on Debian/Ubuntu).

If you're using Chef, use the
[example cookbook](https://github.com/mperham/sidekiq/tree/master/examples/chef/cookbooks/sidekiq)
(modified for your environment), and Opscode's
[runit cookbook](http://ckbk.it/runit) to set up the service.

Author: Joshua Timberman <joshua@opscode.com>

Runit is written by Gerrit Pape.

* http://smarden.org/runit
