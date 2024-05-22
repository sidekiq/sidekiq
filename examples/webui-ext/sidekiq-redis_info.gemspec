# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "sidekiq-redis_info"
  spec.version = "1.0"
  spec.authors = ["Mike Perham"]
  spec.email = ["mike@perham.net"]
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.6.0"
  spec.summary = spec.description = "sidekiq example"
  spec.homepage = "https://sidekiq.org"

  spec.metadata["allowed_push_host"] = "NONE"
  spec.metadata["homepage_uri"] = spec.homepage

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.require_paths = ["lib"]
end
