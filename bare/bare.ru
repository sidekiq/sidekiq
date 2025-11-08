require "securerandom"
require "sidekiq/web"

secret_key = SecureRandom.hex(32)
use Rack::Session::Cookie, secret: secret_key, same_site: true, max_age: 86400
run Sidekiq::Web
