Sidekiq::Client.redis = Sidekiq::RedisConnection.create(:namespace => 'resque')
