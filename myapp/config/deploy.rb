require 'bundler/capistrano'
require 'sidekiq/capistrano'

set :scm, :git
set :repository, 'git@github.com:mperham/sidekiq'
ssh_options[:forward_agent] = true

default_run_options[:pty] = true # needed to run sudo
set :user, 'mperham'
set :application, "myapp"
set :deploy_via, :remote_cache

role :web, "localhost"
role :app, "localhost"
role :db,  "localhost", :primary => true
