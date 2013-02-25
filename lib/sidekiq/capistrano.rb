Capistrano::Configuration.instance.load do
  before "deploy:update_code", "sidekiq:quiet"
  after "deploy:stop",    "sidekiq:stop"
  after "deploy:start",   "sidekiq:start"
  before "deploy:restart", "sidekiq:restart"

  _cset(:sidekiq_cmd) { "#{fetch(:bundle_cmd, "bundle")} exec sidekiq" }
  _cset(:sidekiqctl_cmd) { "#{fetch(:bundle_cmd, "bundle")} exec sidekiqctl" }
  _cset(:sidekiq_timeout)   { 10 }
  _cset(:sidekiq_role)      { :app }
  _cset(:sidekiq_pid)       { "#{current_path}/tmp/pids/sidekiq.pid" }
  _cset(:sidekiq_processes) { 1 }

  namespace :sidekiq do
    def for_each_process(&block)
      fetch(:sidekiq_processes).times do |idx|
        yield((idx == 0 ? "#{fetch(:sidekiq_pid)}" : "#{fetch(:sidekiq_pid)}-#{idx}"), idx)
      end
    end

    desc "Quiet sidekiq (stop accepting new work)"
    task :quiet, :roles => lambda { fetch(:sidekiq_role) }, :on_no_matching_servers => :continue do
      for_each_process do |pid_file, idx|
        run "if [ -d #{current_path} ] && [ -f #{pid_file} ] && kill -0 `cat #{pid_file}`> /dev/null 2>&1; then cd #{current_path} && #{fetch(:sidekiqctl_cmd)} quiet #{pid_file} ; else echo 'Sidekiq is not running'; fi"
      end
    end

    desc "Stop sidekiq"
    task :stop, :roles => lambda { fetch(:sidekiq_role) }, :on_no_matching_servers => :continue do
      for_each_process do |pid_file, idx|
        run "if [ -d #{current_path} ] && [ -f #{pid_file} ] && kill -0 `cat #{pid_file}`> /dev/null 2>&1; then cd #{current_path} && #{fetch(:sidekiqctl_cmd)} stop #{pid_file} #{fetch :sidekiq_timeout} ; else echo 'Sidekiq is not running'; fi"
      end
    end

    desc "Start sidekiq"
    task :start, :roles => lambda { fetch(:sidekiq_role) }, :on_no_matching_servers => :continue do
      rails_env = fetch(:rails_env, "production")
      for_each_process do |pid_file, idx|
        run "cd #{current_path} ; nohup #{fetch(:sidekiq_cmd)} -e #{rails_env} -C #{current_path}/config/sidekiq.yml -i #{idx} -P #{pid_file} >> #{current_path}/log/sidekiq.log 2>&1 &", :pty => false
      end
    end

    desc "Restart sidekiq"
    task :restart, :roles => lambda { fetch(:sidekiq_role) }, :on_no_matching_servers => :continue do
      stop
      start
    end

  end
end
