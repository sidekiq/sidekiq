This is a "service" directory for sidekiq. You should probably modify
the relevant paths in the run script, and the log/run script, if
necessary. It assumes a "sidekiq" user is created that will run the
sidekiq process. To supervise under runit, link this directory to the
runsvdir for your system (e.g., `/etc/service` on Debian/Ubuntu).
