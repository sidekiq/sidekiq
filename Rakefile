require "bundler/gem_tasks"
require "rake/testtask"
require "standard/rake"

# If you want to generate API docs:
#   gem install yard && yard && open doc/index.html
# YARD readme: https://rubydoc.info/gems/yard/file/README.md
# YARD tags: https://www.rubydoc.info/gems/yard/file/docs/Tags.md
# YARD cheatsheet: https://gist.github.com/phansch/db18a595d2f5f1ef16646af72fe1fb0e

# To check code coverage, comment in simplecov in the rake file and
# run `COVERAGE=9 bundle exec rake`

Rake::TestTask.new(:test) do |test|
  test.warning = true
  test.pattern = "test/**/test_*.rb"
end

task default: [:standard, :test]
