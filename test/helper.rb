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
ENV['RACK_ENV'] = ENV['RAILS_ENV'] = 'test'

trap 'USR1' do
  threads = Thread.list

  puts
  puts "=" * 80
  puts "Received USR1 signal; printing all #{threads.count} thread backtraces."

  threads.each do |thr|
    description = thr == Thread.main ? "Main thread" : thr.inspect
    puts
    puts "#{description} backtrace: "
    puts thr.backtrace.join("\n")
  end

  puts "=" * 80
end

begin
  require 'pry-byebug'
rescue LoadError
end

require 'minitest/autorun'

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

def with_logging(lvl=Logger::DEBUG)
  old = Sidekiq.logger.level
  begin
    Sidekiq.logger.level = lvl
    yield
  ensure
    Sidekiq.logger.level = old
  end
end
