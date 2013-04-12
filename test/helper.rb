require 'coveralls'
Coveralls.wear! do
  add_filter "/test/"
end

ENV['RACK_ENV'] = ENV['RAILS_ENV'] = 'test'
if ENV.has_key?("SIMPLECOV")
  require 'simplecov'
  SimpleCov.start do
    add_filter "/test/"
  end
end

begin
  require 'pry'
rescue LoadError
end

require 'minitest/unit'
require 'minitest/autorun'
require 'minitest/emoji'

require 'sidekiq'
require 'sidekiq/util'
Sidekiq.logger.level = Logger::ERROR

require 'sidekiq/redis_connection'
REDIS = Sidekiq::RedisConnection.create(:url => "redis://localhost/15", :namespace => 'testy')
