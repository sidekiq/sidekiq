source 'https://rubygems.org'
gemspec

gem 'rails', '~> 4.2'
gem 'simplecov'
gem 'minitest'
gem 'toxiproxy'

platforms :rbx do
  gem 'rubysl', '~> 2.0'         # if using anything in the ruby standard library
  gem 'psych'                    # if using yaml
  gem 'minitest'                 # if using minitest
  gem 'rubinius-developer_tools' # if using any of coverage, debugger, profiler
end

platforms :ruby do
  gem 'sqlite3'
end

platforms :mri do
  gem 'pry-byebug'
end

platforms :jruby do
  gem 'jruby-openssl'
  gem 'activerecord-jdbcsqlite3-adapter'
end
