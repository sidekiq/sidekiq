$TESTING = true
require 'coveralls'
Coveralls.wear! do
  add_filter "/test/"
  add_filter "/myapp/"
end

ENV['RACK_ENV'] = ENV['RAILS_ENV'] = 'test'
if ENV.has_key?("SIMPLECOV")
  require 'simplecov'
  SimpleCov.start do
    add_filter "/test/"
    add_filter "/myapp/"
  end
end

begin
  require 'pry'
rescue LoadError
end

require 'minitest/autorun'
require 'minitest/pride'

require 'celluloid/test'
Celluloid.boot
require 'sidekiq'
require 'sidekiq/util'
Sidekiq.logger.level = Logger::ERROR

Sidekiq::Test = MiniTest::Unit::TestCase

require 'sidekiq/redis_connection'
redis_url = ENV['REDIS_URL'] || 'redis://localhost/15'
REDIS = Sidekiq::RedisConnection.create(:url => redis_url, :namespace => 'testy')

Sidekiq.configure_client do |config|
  config.redis = { :url => redis_url, :namespace => 'testy' }
end
