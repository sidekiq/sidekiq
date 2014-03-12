Sidekiq.configure_client do |config|
  config.redis = { :size => 2, :namespace => 'foo' }
end
Sidekiq.configure_server do |config|
  config.redis = { :size => 25, :namespace => 'foo' }
  config.on(:startup) { puts "Hello!" }
  config.on(:quiet) { puts "Quiet down!" }
  config.on(:shutdown) { puts "Goodbye!" }
end

class EmptyWorker
  include Sidekiq::Worker

  def perform
  end
end
