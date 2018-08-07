# -*- encoding: utf-8 -*-
require File.expand_path('../lib/sidekiq/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Mike Perham"]
  gem.email         = ["mperham@gmail.com"]
  gem.summary       = "Simple, efficient background processing for Ruby"
  gem.description   = "Simple, efficient background processing for Ruby."
  gem.homepage      = "http://sidekiq.org"
  gem.license       = "LGPL-3.0"

  gem.executables   = ['sidekiq', 'sidekiqctl']
  gem.files         = `git ls-files | grep -Ev '^(test|myapp|examples)'`.split("\n")
  gem.test_files    = []
  gem.name          = "sidekiq"
  gem.require_paths = ["lib"]
  gem.version       = Sidekiq::VERSION
  gem.required_ruby_version = ">= 2.2.2"

  gem.add_dependency 'redis', '>= 3.3.5', '< 5'
  gem.add_dependency 'connection_pool', '~> 2.2', '>= 2.2.2'
  gem.add_dependency 'rack-protection', '>= 1.5.0'
end
