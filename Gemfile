source "https://rubygems.org"

gemspec

gem "rake"
gem "rails"
gem "redis-client", github: "redis-rb/redis-client"

# Required for Ruby 3.1
# https://github.com/mikel/mail/pull/1439
gem "net-smtp"
gem "net-imap"
gem "net-pop"

gem "sqlite3", platforms: :ruby
gem "activerecord-jdbcsqlite3-adapter", platforms: :jruby
gem "after_commit_everywhere"

group :test do
  gem "minitest"
  # gem "simplecov"
  # gem "codecov", require: false
end

group :development, :test do
  gem "standard", require: false
  # gem "pry"
  # gem "yalphabetize", require: false
end

group :load_test do
  # gem "toxiproxy"
end
