namespace :load do
  task :defaults do
    set :sidekiq_default_hooks, -> { true }

    set :sidekiq_pid, -> { File.join(shared_path, 'tmp', 'pids', 'sidekiq.pid') }
    set :sidekiq_env, -> { fetch(:rack_env, fetch(:rails_env, fetch(:stage))) }
    set :sidekiq_log, -> { File.join(shared_path, 'log', 'sidekiq.log') }

    # "-d -i INT -P PATH" are added automatically.
    set :sidekiq_options, -> { "-e #{fetch(:sidekiq_env)} -L #{fetch(:sidekiq_log)}" }

    set :sidekiq_timeout, -> { 10 }
    set :sidekiq_role, -> { :app }
    set :sidekiq_processes, -> { 1 }
    # Rbenv and RVM integration
    set :rbenv_map_bins, fetch(:rbenv_map_bins).to_a.concat(%w{ sidekiq sidekiqctl })
    set :rvm_map_bins, fetch(:rvm_map_bins).to_a.concat(%w{ sidekiq sidekiqctl })
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
      yield((idx.zero? ? "#{fetch(:sidekiq_pid)}" : "#{fetch(:sidekiq_pid).gsub('.pid', "-#{idx}.pid")}"), idx)
    end
  end


  task :add_default_hooks do
    after 'deploy:starting', 'sidekiq:quiet'
    after 'deploy:updated', 'sidekiq:stop'
    after 'deploy:reverted', 'sidekiq:stop'
    after 'deploy:published', 'sidekiq:start'
  end

  desc 'Quiet sidekiq (stop processing new tasks)'
  task :quiet do
    on roles fetch(:sidekiq_role) do
      for_each_process do |pid_file, idx|
        if test("[ -f #{pid_file} ]") and test("kill -0 $( cat #{pid_file} )")
          within current_path do
            execute :bundle, :exec, :sidekiqctl, 'quiet', "#{pid_file}"
          end
        end
      end
    end
  end

  desc 'Stop sidekiq'
  task :stop do
    on roles fetch(:sidekiq_role) do
      for_each_process do |pid_file, idx|
        if test("[ -f #{pid_file} ]") and test("kill -0 $( cat #{pid_file} )")
          within current_path do
            execute :bundle, :exec, :sidekiqctl, 'stop', "#{pid_file}", fetch(:sidekiq_timeout)
          end
        end
      end
    end
  end

  desc 'Start sidekiq'
  task :start do
    on roles fetch(:sidekiq_role) do
      within current_path do
        for_each_process do |pid_file, idx|
          command = "-i #{idx} -P #{pid_file} #{fetch(:sidekiq_options)}"
          if defined?(JRUBY_VERSION)
            command = "#{command} >/dev/null 2>&1 &"
            warn 'Since JRuby doesn\'t support Process.daemon, Sidekiq will be running without the -d flag.'
          else
            command = "-d #{command}"
          end
          execute :bundle, :exec, :sidekiq, command
        end
      end
    end
  end

  desc 'Restart sidekiq'
  task :restart do
    invoke 'sidekiq:stop'
    invoke 'sidekiq:start'
  end

end
