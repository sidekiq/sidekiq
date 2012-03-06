Sidekiq.configure_client do |config|
  config.redis = { :size => 2 }
end
Sidekiq.configure_server do |config|
  config.redis = { :size => 25 }
end
