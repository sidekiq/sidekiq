# -*- encoding: utf-8 -*-
require File.expand_path('../lib/sidekiq/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Mike Perham"]
  gem.email         = ["mperham@gmail.com"]
  gem.description   = gem.summary = "Simple, efficient message processing for Ruby"
  gem.homepage      = "http://mperham.github.com/sidekiq"

  gem.executables   = ['sidekiq']
  gem.files         = `git ls-files`.split("\n")
  gem.test_files    = `git ls-files -- test/*`.split("\n")
  gem.name          = "sidekiq"
  gem.require_paths = ["lib"]
  gem.version       = Sidekiq::VERSION
  gem.add_dependency                  'redis'
  gem.add_dependency                  'redis-namespace'
  gem.add_dependency                  'connection_pool'
  gem.add_dependency                  'celluloid'
  gem.add_dependency                  'multi_json'
  gem.add_development_dependency      'minitest'
  gem.add_development_dependency      'rake'
end
