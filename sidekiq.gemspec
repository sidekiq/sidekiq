# -*- encoding: utf-8 -*-
require File.expand_path('../lib/sidekiq/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Mike Perham"]
  gem.email         = ["mperham@gmail.com"]
  gem.description   = gem.summary = "Simple, efficient message processing for Ruby"
  gem.homepage      = "http://sidekiq.org"
  gem.license       = "LGPL-3.0"

  gem.executables   = ['sidekiq', 'sidekiqctl']
  gem.files         = `git ls-files | grep -Ev '^(myapp|examples)'`.split("\n")
  gem.test_files    = `git ls-files -- test/*`.split("\n")
  gem.name          = "sidekiq"
  gem.require_paths = ["lib"]
  gem.version       = Sidekiq::VERSION
  gem.add_dependency                  'redis', '~> 3'
  gem.add_dependency                  'redis-namespace'
  gem.add_dependency                  'connection_pool', '~> 1.0'
  gem.add_dependency                  'celluloid', '~> 0.13.0'
  gem.add_dependency                  'multi_json', '~> 1'
  gem.add_development_dependency      'sinatra'
  gem.add_development_dependency      'slim'
  gem.add_development_dependency      'minitest', '~> 4'
  gem.add_development_dependency      'rake'
  gem.add_development_dependency      'actionmailer', '~> 3'
  gem.add_development_dependency      'activerecord', '~> 3'
  gem.add_development_dependency      'coveralls'
end
