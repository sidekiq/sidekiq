source 'https://rubygems.org'
gemspec

gem 'rails', '>= 5.0.1'
gem "hiredis"
gem 'simplecov'
gem 'minitest'
#gem 'minitest-utils'
gem 'toxiproxy'

# For Redis 4.0 support. Unreleased 9cb81bf.
gem 'redis-namespace', git: 'https://github.com/resque/redis-namespace'

platforms :rbx do
  gem 'rubysl', '~> 2.0'         # if using anything in the ruby standard library
  gem 'psych'                    # if using yaml
  gem 'rubinius-developer_tools' # if using any of coverage, debugger, profiler
end

platforms :ruby do
  gem 'sqlite3'
end

platforms :mri do
  gem 'pry-byebug'
  gem 'ruby-prof'
end

#platforms :jruby do
  #gem 'jruby-openssl'
  #gem 'activerecord-jdbcsqlite3-adapter'
#end
