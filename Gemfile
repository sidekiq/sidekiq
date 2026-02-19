source "https://gem.coop"

gemspec
# gem "connection_pool", path: "../connection_pool"

gem "rake"
RAILS_VERSION = "~> #{ENV.fetch("RAILS_VERSION", "8")}.0"
gem "actionmailer", RAILS_VERSION
gem "actionpack", RAILS_VERSION
gem "activejob", RAILS_VERSION
gem "activerecord", RAILS_VERSION
gem "railties", RAILS_VERSION
gem "redis-client"
# gem "bumbler"
# gem "debug"
gem "ratatui_ruby"

gem "sqlite3", "~> 2.2", platforms: :ruby
gem "activerecord-jdbcsqlite3-adapter", platforms: :jruby
gem "after_commit_everywhere", require: false
gem "yard"
gem "csv"
gem "vernier" unless RUBY_VERSION < "3"
gem "webrick"

group :test do
  # Can't use minitest 6 until our oldest version of Rails works with it
  gem "minitest", "<6"
  # gem "minitest-mock"
  gem "simplecov"
  gem "debug"
end

group :development, :test do
  gem "standard", require: false
  gem "herb", require: false
end

group :load_test do
  gem "toxiproxy"
  gem "ruby-prof"
end
