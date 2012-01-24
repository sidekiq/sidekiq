require 'rake/testtask'
Rake::TestTask.new(:test) do |test|
  test.libs << 'test'
  test.warning = true
  test.pattern = 'test/**/test_*.rb'
end

task :default => :test

desc 'Code coverage analysis'
task :cov => [:simplecov, :test]
task :simplecov do
  require 'simplecov'
  SimpleCov.start
end
