source 'https://rubygems.org'

gemspec

gem 'rake'
gem 'redis-namespace'
gem 'rails', '~> 5.2'
gem 'sqlite3', platforms: :ruby
gem 'activerecord-jdbcsqlite3-adapter', platforms: :jruby

group :development do
  gem 'appraisal'
end

group :test do
  gem 'minitest'
  gem 'minitest-focus'
  gem 'minitest-reporters'
  gem 'simplecov'
end

group :development, :test do
  gem 'pry-byebug', platforms: :mri
end

group :load_test do
  gem 'hiredis'
  gem 'toxiproxy'
end
