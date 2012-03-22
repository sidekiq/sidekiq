#
# Cookbook Name:: sidekiq
# Recipe:: default
#
role = node[:instance_role]
if role == 'solo' || (role == 'util' && node[:name] =~ /sidekiq/)

  # for now
  worker_count = 1

  node[:applications].each do |app, data|
    template "/etc/monit.d/sidekiq_#{app}.monitrc" do 
      owner 'root' 
      group 'root' 
      mode 0644 
      source "monitrc.conf.erb" 
      variables({ 
        :num_workers => worker_count,
        :app_name => app, 
        :rails_env => node[:environment][:framework_env] 
      }) 
    end

    template "/engineyard/bin/sidekiq" do
      owner 'root'
      group 'root' 
      mode 0755
      source "sidekiq.erb" 
    end

    worker_count.times do |count|
      template "/data/#{app}/shared/config/sidekiq_#{count}.yml" do
        owner node[:owner_name]
        group node[:owner_name]
        mode 0644
        source "sidekiq.yml.erb"
        variables({
          :require => "/data/#{app}/current"
        })
      end
    end

    execute "ensure-sidekiq-is-setup-with-monit" do 
      command %Q{ 
        monit reload 
      } 
    end

    execute "restart-sidekiq" do 
      command %Q{ 
        echo "sleep 20 && monit -g #{app}_sidekiq restart all" | at now 
      }
    end
  end 
end
