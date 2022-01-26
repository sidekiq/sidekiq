source "https://rubygems.org"

gemspec

gem "rake"
gem "redis-namespace"
gem "rails", "~> 7.0"

# Required for Ruby 3.1
# https://github.com/mikel/mail/pull/1439
gem "net-smtp", platforms: :mri, require: false

gem "sqlite3", platforms: :ruby
gem "activerecord-jdbcsqlite3-adapter", platforms: :jruby

group :test do
  gem "minitest"
  gem "simplecov"
  gem "codecov", require: false
end

group :development, :test do
  gem "standard", require: false
end

group :load_test do
  gem "hiredis"
  gem "toxiproxy"
end
