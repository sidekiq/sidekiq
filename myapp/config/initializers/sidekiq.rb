Sidekiq.configure_client do |config|
  config.redis = { :namespace => 'resque', :size => 2 }
end
Sidekiq.configure_server do |config|
  config.redis = { :namespace => 'resque', :size => 25 }
end
