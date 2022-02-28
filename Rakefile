require "bundler/gem_tasks"
require "rake/testtask"
require "standard/rake"

Rake::TestTask.new(:test) do |test|
  test.warning = true
  test.pattern = "test/**/test_*.rb"
end

task :yalphabetize do
  system "bundle exec yalphabetize"
end

task default: [:standard, :yalphabetize, :test]
