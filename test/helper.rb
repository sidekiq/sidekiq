# frozen_string_literal: true

require 'bundler/setup'
Bundler.require(:default, :test)

require 'minitest/autorun'

$TESTING = true
# disable minitest/parallel threads
ENV["N"] = "0"

if ENV["COVERAGE"]
  require 'simplecov'
  SimpleCov.start do
    add_filter "/test/"
    add_filter "/myapp/"
  end
end

ENV['REDIS_URL'] ||= 'redis://localhost/15'

Sidekiq.logger = ::Logger.new(STDOUT)
Sidekiq.logger.level = Logger::ERROR

def capture_logging(lvl=Logger::INFO)
  old = Sidekiq.logger
  begin
    out = StringIO.new
    logger = ::Logger.new(out)
    logger.level = lvl
    Sidekiq.logger = logger
    yield
    out.string
  ensure
    Sidekiq.logger = old
  end
end

def with_logging(lvl=Logger::DEBUG)
  old = Sidekiq.logger.level
  begin
    Sidekiq.logger.level = lvl
    yield
  ensure
    Sidekiq.logger.level = old
  end
end
