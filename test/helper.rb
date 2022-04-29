# frozen_string_literal: true

require "bundler/setup"
Bundler.require(:default, :test)

require "minitest/pride"
require "minitest/autorun"

$TESTING = true
# disable minitest/parallel threads
ENV["MT_CPU"] = "0"
ENV["N"] = "0"
# Disable any stupid backtrace cleansers
ENV["BACKTRACE"] = "1"

if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start do
    enable_coverage :branch
    add_filter "/test/"
    add_filter "/myapp/"
  end
  if ENV["CI"]
    require "codecov"
    SimpleCov.formatter = SimpleCov::Formatter::Codecov
  end
end

ENV["REDIS_URL"] ||= "redis://localhost/15"

Sidekiq.logger = ::Logger.new(STDOUT)
Sidekiq.logger.level = Logger::ERROR

if ENV["SIDEKIQ_REDIS_CLIENT"]
  Sidekiq::RedisConnection.adapter = :redis_client
end

def capture_logging(lvl = Logger::INFO)
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
