source "https://rubygems.org"

gemspec

gem "rake"
gem "redis-namespace"
gem "rails", ">= 6.0.2"
gem "sqlite3", platforms: :ruby
gem "activerecord-jdbcsqlite3-adapter", platforms: :jruby

group :test do
  gem "minitest"
  gem "simplecov"
  gem "codecov", require: false
end

group :development, :test do
  gem "standard"
end

group :load_test do
  gem "hiredis"
  gem "toxiproxy"
end
