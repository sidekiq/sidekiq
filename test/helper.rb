$TESTING = true
if false
  require 'simplecov'
  SimpleCov.start
end

require 'minitest/unit'
require 'minitest/pride'
require 'minitest/autorun'

require 'sidekiq/util'
Sidekiq::Util.logger.level = Logger::ERROR
