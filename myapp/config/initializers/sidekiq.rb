Sidekiq.configure do |config|
  config.redis = Sidekiq::RedisConnection.create(:namespace => 'resque', :size => 5)
end
