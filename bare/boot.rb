Sidekiq.configure_server do |config|
  config.redis = {db: 14}
  config.capsule("single") do |cap|
    cap.concurrency = 1
    cap.queues = %w[single_threaded]
  end
end
