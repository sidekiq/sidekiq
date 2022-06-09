require "bundler/gem_tasks"
require "rake/testtask"
require "standard/rake"
require "rdoc/task"

RDoc::Task.new do |rdoc|
  rdoc.main = "docs/rdoc.rdoc"
  rdoc.rdoc_files.include("docs/rdoc.rdoc",
    "lib/sidekiq/api.rb",
    "lib/sidekiq/client.rb",
    "lib/sidekiq/worker.rb",
    "lib/sidekiq/job.rb")
end

Rake::TestTask.new(:test) do |test|
  test.warning = true
  test.pattern = "test/**/test_*.rb"
end

task default: [:standard, :test]
