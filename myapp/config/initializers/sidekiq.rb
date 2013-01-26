Sidekiq.configure_client do |config|
  config.redis = { :size => 2, :namespace => 'foo' }
end
Sidekiq.configure_server do |config|
  config.redis = { :size => 25, :namespace => 'foo' }
end
