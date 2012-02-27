Capistrano::Configuration.instance.load do
  after "deploy", "sidekiq:restart"

  namespace :sidekiq do

    desc "Force stop sidekiq"
    task :kill do
      run "cd #{current_path} && kill `cat tmp/pids/sidekiq.pid` && sleep 5 && kill -9 `cat tmp/pids/sidekiq.pid`"
    end

    desc "Stop sidekiq"
    task :stop do
      run "cd #{current_path} && kill `cat tmp/pids/sidekiq.pid`"
    end

    desc "Start sidekiq"
    task :start do
      rails_env = fetch(:rails_env, "production")
      run "cd #{current_path} && bundle exec sidekiq -e #{rails_env} -C config/sidekiq.yml -P tmp/pids/sidekiq.pid >> log/sidekiq.log &"
    end

    desc "Restart sidekiq"
    task :restart do
      stop
      start
    end

  end
end
