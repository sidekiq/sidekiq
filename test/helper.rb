$CELLULOID_DEBUG = false
$TESTING = true
if ENV["COVERAGE"]
  require 'simplecov'
  SimpleCov.start do
    add_filter "/test/"
    add_filter "/myapp/"
  end
end
ENV['RACK_ENV'] = ENV['RAILS_ENV'] = 'test'

begin
  require 'pry-byebug'
rescue LoadError
end

require 'minitest/autorun'
require 'minitest/pride'

require 'celluloid/current'
require 'celluloid/test'
Celluloid.boot
require 'sidekiq'
require 'sidekiq/util'
Sidekiq.logger.level = Logger::ERROR

Sidekiq::Test = Minitest::Test

require 'sidekiq/redis_connection'
REDIS_URL = ENV['REDIS_URL'] || 'redis://localhost/15'
REDIS = Sidekiq::RedisConnection.create(:url => REDIS_URL, :namespace => 'testy')

Sidekiq.configure_client do |config|
  config.redis = { :url => REDIS_URL, :namespace => 'testy' }
end

def capture_logging(lvl=Logger::INFO)
  old = Sidekiq.logger
  begin
    out = StringIO.new
    logger = Logger.new(out)
    logger.level = lvl
    Sidekiq.logger = logger
    yield
    out.string
  ensure
    Sidekiq.logger = old
  end
end
