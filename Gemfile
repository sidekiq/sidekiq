source "https://gem.coop"
gemspec

# gem "connection_pool", path: "../connection_pool"
# gem "rake"

gem "redis-client"
gem "vernier"

group :tui do
  gem "ratatui_ruby"
end

RAILS_VERSION = "~> #{ENV.fetch("RAILS_VERSION", "8")}.0"
group :test do
  gem "actionmailer", RAILS_VERSION
  gem "actionpack", RAILS_VERSION
  gem "activejob", RAILS_VERSION
  gem "activerecord", RAILS_VERSION
  gem "railties", RAILS_VERSION

  gem "activerecord-jdbcsqlite3-adapter", platforms: :jruby
  gem "sqlite3", platforms: :ruby
  gem "after_commit_everywhere", require: false

  # Can't use minitest 6 until our oldest version of Rails works with it
  gem "minitest", "<6"
  # gem "minitest-mock"
  gem "simplecov"
  gem "debug"
  gem "csv"
end

group :development do
  gem "standard", require: false
  gem "herb", require: false
end

group :load_test do
  gem "toxiproxy"
  gem "ruby-prof"
  # gem "memory_profiler"
  # gem "derailed_benchmarks"
end
