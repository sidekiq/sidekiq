require "bundler/gem_tasks"
require "rake/testtask"
require "standard/rake"
require "yard"
require "yard/rake/yardoc_task"

# If you want to generate the docs, run yarddoc from your terminal
# https://rubydoc.info/gems/yard/file/README.md

Rake::TestTask.new(:test) do |test|
  test.warning = true
  test.pattern = "test/**/test_*.rb"
end

namespace :test do
  task :redis_client do
    previous = ENV["SIDEKIQ_REDIS_CLIENT"]
    ENV["SIDEKIQ_REDIS_CLIENT"] = "1"
    Rake::Task[:test].execute
  ensure
    if previous
      ENV["SIDEKIQ_REDIS_CLIENT"] = previous
    else
      ENV.delete("SIDEKIQ_REDIS_CLIENT")
    end
  end
end

task default: [:standard, :test, "test:redis_client"]
