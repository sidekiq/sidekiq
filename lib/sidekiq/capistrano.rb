Capistrano::Configuration.instance.load do
  before "deploy", "sidekiq:quiet"
  after "deploy", "sidekiq:restart"

  _cset(:sidekiq_timeout) { 5 }

  namespace :sidekiq do

    desc "Quiet sidekiq (stop accepting new work)"
    task :quiet do
      run "cd #{current_path} && kill -USR1 `cat #{current_path}/tmp/pids/sidekiq.pid`"
    end

    desc "Stop sidekiq"
    task :stop do
      run "cd #{current_path} && kill `cat #{current_path}/tmp/pids/sidekiq.pid` && sleep #{fetch :sidekiq_timeout} && kill -9 `cat #{current_path}/tmp/pids/sidekiq.pid` && rm #{current_path}/tmp/pids/sidekiq.pid"
    end

    desc "Start sidekiq"
    task :start do
      rails_env = fetch(:rails_env, "production")
      run "cd #{current_path} && nohup bundle exec sidekiq -e #{rails_env} -C #{current_path}/config/sidekiq.yml -P #{current_path}/tmp/pids/sidekiq.pid >> #{current_path}/log/sidekiq.log &"
    end

    desc "Restart sidekiq"
    task :restart do
      stop
      start
    end

  end
end
