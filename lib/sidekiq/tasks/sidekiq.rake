namespace :load do
  task :defaults do

    set :sidekiq_default_hooks, ->{ true }

    # If you need a special boot commands
    #
    # set :sidekiq_cmd,           ->{ "bundle exec sidekiq"  }
    # set :sidekiqctl_cmd,        ->{ "bundle exec sidekiqctl" }
    set :sidekiq_cmd,           ->{  }
    set :sidekiqctl_cmd,        ->{  }

    # If this changes, you'll need to manually
    # stop the existing sidekiq process.
    set :sidekiq_pid,             ->{ "tmp/sidekiq.pid" }

    # "-d -i INT -P PATH" are added automatically.
    set :sidekiq_options,       ->{ "-e #{fetch(:rails_env, 'production')} -L #{current_path}/log/sidekiq.log" }

    set :sidekiq_timeout,       ->{ 10 }
    set :sidekiq_role,            ->{ :app }
    set :sidekiq_processes,   ->{ 1 }
  end
end

namespace :deploy do
  before :starting, :check_sidekiq_hooks do
    invoke 'sidekiq:add_default_hooks' if fetch(:sidekiq_default_hooks)
  end
end

namespace :sidekiq do
  def for_each_process(&block)
    fetch(:sidekiq_processes).times do |idx|
      yield((idx == 0 ? "#{fetch(:sidekiq_pid)}" : "#{fetch(:sidekiq_pid)}-#{idx}"), idx)
    end
  end

  def pid_full_path(pid_path)
    if pid_path.start_with?("/")
      pid_path
    else
      "#{current_path}/#{pid_path}"
    end
  end

  task :add_default_hooks do
    after 'deploy:starting',  'sidekiq:quiet'
    after 'deploy:updated',   'sidekiq:stop'
    after 'deploy:reverted',  'sidekiq:stop'
    after 'deploy:published', 'sidekiq:start'
  end

  desc "Quiet sidekiq (stop accepting new work)"
  task :quiet do
    on roles fetch(:sidekiq_role) do
      for_each_process do |pid_file, idx|
        if test "[ -f #{pid_full_path(pid_file)} ]"
          within current_path do
            if fetch(:sidekiqctl_cmd)
              execute fetch(:sidekiqctl_cmd), 'quiet', "#{pid_full_path(pid_file)}"
            else
              execute :bundle, :exec, :sidekiqctl, 'quiet', "#{pid_full_path(pid_file)}"
            end
          end
        end
      end
    end
  end

  desc "Stop sidekiq"
  task :stop do
    on roles fetch(:sidekiq_role) do
      for_each_process do |pid_file, idx|
        if test "[ -f #{pid_full_path(pid_file)} ]"
          within current_path do
            if fetch(:sidekiqctl_cmd)
              execute fetch(:sidekiqctl_cmd), 'stop', "#{pid_full_path(pid_file)}", fetch(:sidekiq_timeout)
            else
              execute :bundle, :exec, :sidekiqctl, 'stop', "#{pid_full_path(pid_file)}", fetch(:sidekiq_timeout)
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
          if !defined? JRUBY_VERSION
            if fetch(:sidekiq_cmd)
              execute fetch(:sidekiq_cmd), "-d -i #{idx} -P #{pid_full_path(pid_file)} #{fetch(:sidekiq_options)}"
            else
              execute :bundle, :exec, :sidekiq, "-d -i #{idx} -P #{pid_full_path(pid_file)} #{fetch(:sidekiq_options)}"
            end
          else
            execute "echo 'Since JRuby doesn't support Process.daemon, Sidekiq will be running without the -d flag."
            if fetch(:sidekiq_cmd)
              execute fetch(:sidekiq_cmd), "-i #{idx} -P #{pid_full_path(pid_file)} #{fetch(:sidekiq_options)} >/dev/null 2>&1 &"
            else
              execute :bundle, :exec, :sidekiq, "-i #{idx} -P #{pid_full_path(pid_file)} #{fetch(:sidekiq_options)} >/dev/null 2>&1 &"
            end
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

end
