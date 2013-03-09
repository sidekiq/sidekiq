# Sidekiq as a service using Upstart

Manage multiple Sidekiq servers as services on the same box using Ubuntu upstart.

## Installation 

    # Copy the scripts to services directory 
    sudo cp sidekiq.conf sidekiq-manager.conf /etc/init
    
    # Create an empty configuration file
    sudo touch /etc/sidekiq.conf

## Managing the dojo 

Sidekiq-enabled apps are referenced in /etc/sidekiq.conf by default. Add each app's path as a new line, e.g.:

```
/home/apps/my-cool-ruby-app,1
/home/apps/another-app/current,2
```

The format is:

`app,number_of_workers`

Start the jungle running:

`sudo start sidekiq-manager`

This script will run at boot time.

Start a single sidekiq like this:

`sudo start sidekiq app=/path/to/app index=0`

## Logs

Everything is logged by upstart, defaulting to `/var/log/upstart`.

Each sidekiq instance is named after its directory, so for an app called `/home/apps/my-app` with one process the log file would be `/var/log/upstart/sidekiq-_home_apps_my-app-0.log`.

## Conventions 

* The script expects:
  * a config file to exist under `config/sidekiq.yml` in your app. E.g.: `/home/apps/my-app/config/sidekiq.yml`.
  * a temporary folder to put the processes PIDs exists called `tmp/sidekiq`. E.g.: `/home/apps/my-app/tmp/sidekiq`.

You can always change those defaults by editing the scripts.

## Before starting...

You need to customise `sidekiq.conf` to:

* Set the right user your app should be running on unless you want root to execute it!
  * Look for `setuid apps` and `setgid apps`, uncomment those lines and replace `apps` to whatever your deployment user is.
  * Replace `apps` on the paths (or set the right paths to your user's home) everywhere else.
* Uncomment the source lines for `rbenv` or `rvm` support unless you use a system wide installation of Ruby.
