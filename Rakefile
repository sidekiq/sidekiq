require 'rake/testtask'
Rake::TestTask.new(:test) do |test|
  test.libs << 'test'
  test.warning = true
  test.pattern = 'test/**/test_*.rb'
end

task :default => :test
