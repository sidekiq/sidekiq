namespace :sidekiq do
  def for_each_process(&block)
    fetch(:sidekiq_processes).times do |idx|
      yield((idx == 0 ? "#{fetch(:sidekiq_pid)}" : "#{fetch(:sidekiq_pid)}-#{idx}"), idx)
    end
  end

  desc "Quiet sidekiq (stop accepting new work)"
  task :quiet do
    on roles fetch(:sidekiq_role) do
      within current_path do
        for_each_process do |pid_file, idx|
          execute "if [ -f #{pid_file} ] && kill -0 `cat #{pid_file}`> /dev/null 2>&1; #{fetch(:sidekiqctl_cmd)} quiet #{pid_file} ; else echo 'Sidekiq is not running'; fi"
        end
      end
    end
  end


  desc "Stop sidekiq"
  task :stop do
    on roles fetch(:sidekiq_role) do
      within current_path do
        for_each_process do |pid_file, idx|
          execute "if [ -f #{pid_file} ] && kill -0 `cat #{pid_file}`> /dev/null 2>&1; then #{fetch(:sidekiqctl_cmd)} stop #{pid_file} #{fetch :sidekiq_timeout} ; else echo 'Sidekiq is not running'; fi"
        end
      end
    end
  end

  desc "Start sidekiq"
  task :start do
    on roles fetch(:sidekiq_role) do
      within current_path do
        rails_env = fetch(:rails_env, "production")
        for_each_process do |pid_file, idx|
          execute "nohup #{fetch(:sidekiq_cmd)} -e #{rails_env} -C #{current_path}/config/sidekiq.yml -i #{idx} -P #{pid_file} >> #{current_path}/log/sidekiq.log 2>&1 &"
        end
      end
    end
  end

  desc "Restart sidekiq"
  task :restart do
    on roles fetch(:sidekiq_role) do
      stop
      start
    end
  end

  before 'deploy:updating', 'sidekiq:quiet'
  after  'deploy:stop',     'sidekiq:stop'
  after  'deploy:start',    'sidekiq:start'
  before 'deploy:restart',  'sidekiq:restart'
  
end

namespace :load do
  task :defaults do
    set :sidekiq_default_hooks, ->{ true }
    set :sidekiq_cmd,           ->{ :sidekiq }
    set :sidekiqctl_cmd,        ->{ :sidekiqctl }
    set :sidekiq_timeout,       ->{ 10 }
    set :sidekiq_role,          ->{ :app }
    set :sidekiq_pid,           ->{ "tmp/pids/sidekiq.pid" }
    set :sidekiq_processes,     ->{ 1 }
  end
end


__END__
  desc "Update application's crontab entries using Whenever"
  task :update_crontab do
    on roles fetch(:whenever_roles) do
      within release_path do
        execute fetch(:whenever_command), fetch(:whenever_update_flags)
      end
    end
  end

  desc "Clear application's crontab entries using Whenever"
  task :clear_crontab do
    on roles fetch(:whenever_roles) do
      within release_path do
        execute %{#{fetch(:whenever_command)} #{fetch(:whenever_clear_flags)}}
      end
    end
  end
