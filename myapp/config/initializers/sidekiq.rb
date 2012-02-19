Sidekiq.redis = Sidekiq::RedisConnection.create(:namespace => 'resque', :size => 5)
