namespace :load do
  task :defaults do

    set :sidekiq_default_hooks, ->{ true }

    # If you need a special boot commands
    #
    # set :sidekiq_cmd,           ->{ "bundle exec sidekiq"  }
    # set :sidekiqctl_cmd,        ->{ "bundle exec sidekiqctl" }
    set :sidekiq_cmd,           ->{  }
    set :sidekiqctl_cmd,        ->{  }

    # must be relative to Rails.root. If this changes, you'll need to manually
    # stop the existing sidekiq process.
    set :sidekiq_pid,             ->{ "tmp/sidekiq.pid" }

    # "-d -i INT -P PATH" are added automatically.
    set :sidekiq_options,       ->{ "-e #{fetch(:rails_env, 'production')} -C #{current_path}/config/sidekiq.yml -L #{current_path}/log/sidekiq.log" }

    set :sidekiq_timeout,       ->{ 10 }
    set :sidekiq_role,            ->{ :app }
    set :sidekiq_processes,   ->{ 1 }
  end
end

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
          if test "[ -f #{current_path}/#{pid_file} ]"
            if fetch(:sidekiqctl_cmd)
              execute fetch(:sidekiqctl_cmd), 'quiet', "#{current_path}/#{pid_file}"
            else
              execute :bundle, :exec, :sidekiqctl, 'quiet', "#{current_path}/#{pid_file}"
            end
          end
        end
      end
    end
  end

  desc "Stop sidekiq"
  task :stop do
    on roles fetch(:sidekiq_role) do
      within current_path do
        for_each_process do |pid_file, idx|
          if test "[ -f #{current_path}/#{pid_file} ]"
            if fetch(:sidekiqctl_cmd)
              execute fetch(:sidekiqctl_cmd), 'stop', "#{current_path}/#{pid_file}", fetch(:sidekiq_timeout)
            else
              execute :bundle, :exec, :sidekiqctl, 'stop', "#{current_path}/#{pid_file}", fetch(:sidekiq_timeout)
            end
          end
        end
      end
    end
  end

  desc "Start sidekiq"
  task :start do
    on roles fetch(:sidekiq_role) do
      rails_env = fetch(:rails_env, "production")
      within current_path do
        for_each_process do |pid_file, idx|
          if fetch(:sidekiq_cmd)
            execute fetch(:sidekiq_cmd), "-d -i #{idx} -P #{pid_file} #{fetch(:sidekiq_options)}"
          else
            execute :bundle, :exec, :sidekiq, "-d -i #{idx} -P #{pid_file} #{fetch(:sidekiq_options)}"
          end
        end
      end
    end
  end

  desc "Restart sidekiq"
  task :restart do
    invoke 'sidekiq:stop'
    invoke 'sidekiq:start'
  end

  if fetch(:sidekiq_default_hooks)
    after 'deploy:starting',  'sidekiq:quiet'
    after 'deploy:updated',   'sidekiq:stop'
    after 'deploy:reverted',  'sidekiq:stop'
    after 'deploy:published', 'sidekiq:start'
  end

end
