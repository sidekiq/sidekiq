require_relative 'lib/sidekiq/version'

Gem::Specification.new do |gem|
  gem.authors       = ["Mike Perham"]
  gem.email         = ["mperham@gmail.com"]
  gem.summary       = "Simple, efficient background processing for Ruby"
  gem.description   = "Simple, efficient background processing for Ruby."
  gem.homepage      = "http://sidekiq.org"
  gem.license       = "LGPL-3.0"

  gem.executables   = ['sidekiq', 'sidekiqctl']
  gem.files         = `git ls-files | grep -Ev '^(test|myapp|examples)'`.split("\n")
  gem.name          = "sidekiq"
  gem.version       = Sidekiq::VERSION
  gem.required_ruby_version = ">= 2.2.2"

  gem.add_dependency 'redis', '>= 3.3.5', '< 4.2'
  gem.add_dependency 'connection_pool', '~> 2.2', '>= 2.2.2'
  gem.add_dependency 'rack', '~> 2.0'
  gem.add_dependency 'rack-protection', '>= 1.5.0'
end
