# Easiest way to run Sidekiq::Web.
# Run with "bundle exec rackup simple.ru"

require 'sidekiq'

# A Web process always runs as client, no need to configure server
Sidekiq.configure_client do |config|
  config.redis = { url: 'redis://localhost:6379/0', size: 1 }
end

Sidekiq::Client.push('class' => "HardWorker", 'args' => [])

require 'sidekiq/web'

# In a multi-process deployment, all Web UI instances should share
# this secret key so they can all decode the encrypted browser cookies
# and provide a working session.
# Rails does this in /config/initializers/secret_token.rb
secret_key = SecureRandom.hex(32)
use Rack::Session::Cookie, secret: secret_key
run Sidekiq::Web
