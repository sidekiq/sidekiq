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
    minimum_coverage 90
  end
end

ENV["REDIS_URL"] ||= "redis://localhost/15"

Sidekiq.logger = ::Logger.new($stdout)
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

module Sidekiq
  def self.reset!
    @config = DEFAULTS.dup
  end
end

Signal.trap("TTIN") do
  Thread.list.each do |thread|
    puts "Thread TID-#{(thread.object_id ^ ::Process.pid).to_s(36)} #{thread.name}"
    if thread.backtrace
      puts thread.backtrace.join("\n")
    else
      puts "<no backtrace available>"
    end
  end
end
