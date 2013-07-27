require 'sidekiq'

Sidekiq.configure_client do |config|
  config.redis = { :size => 1 }
end

#Sidekiq.redis {|conn| conn.flushdb }
#10.times do |idx|
  #Sidekiq::Client.push('class' => 'HardWorker', 'args' => ['foo', 0.1, idx])
#end

#Sidekiq.redis { |conn| conn.zadd('retry', Time.now.utc.to_f + 3000, MultiJson.encode({
  #'class' => 'HardWorker', 'args' => ['foo', 0.1, Time.now.to_f],
  #'queue' => 'default', 'error_message' => 'No such method', 'error_class' => 'NoMethodError',
  #'failed_at' => Time.now.utc, 'retry_count' => 0 })) }

require 'sidekiq/web'
run Sidekiq::Web
