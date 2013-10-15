namespace :load do
  task :defaults do
                                  # An issue with sshkit requires that the following two lines 
                                  # be added to your config/deploy.rb file.  This is necessary 
                                  # for sshkit to cd to the correct directory and then run the command.
                                  #
                                  # SSHKit.config.command_map[:sidekiq] = "bundle exec sidekiq"
                                  # SSHKit.config.command_map[:sidekiqctl] = "bundle exec sidekiqctl"
    set :sidekiq_cmd,           ->{ :sidekiq }
    set :sidekiqctl_cmd,        ->{ :sidekiqctl }

                                  # must be relative to Rails.root. If this changes, you'll need to manually
                                  # stop the existing sidekiq process.
    set :sidekiq_pid,           ->{ "tmp/sidekiq.pid" }

                                  # "-d -i INT -P PATH" are added automatically.
    set :sidekiq_options,       ->{ "-e #{fetch(:rails_env, 'production')} -L #{current_path}/log/sidekiq.log" }

    set :sidekiq_timeout,       ->{ 10 }
    set :sidekiq_role,          ->{ :app }
    set :sidekiq_processes,     ->{ 1 }
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
            execute fetch(:sidekiqctl_cmd), 'quiet', pid_file
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
            execute fetch(:sidekiqctl_cmd), 'stop', pid_file, fetch(:sidekiq_timeout)
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
          execute fetch(:sidekiq_cmd), "-d -i #{idx} -P #{pid_file} #{fetch(:sidekiq_options)}" 
        end
      end
    end
  end

  desc "Restart sidekiq"
  task :restart do
    on roles fetch(:sidekiq_role) do
      invoke 'sidekiq:stop'
      invoke 'sidekiq:start'
    end
  end

  after 'deploy:starting',  'sidekiq:quiet'
  after 'deploy:updated',   'sidekiq:stop'
  after 'deploy:reverted',  'sidekiq:stop'
  after 'deploy:published', 'sidekiq:start'
  
end
