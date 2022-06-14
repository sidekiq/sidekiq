require "bundler/gem_tasks"
require "rake/testtask"
require "standard/rake"
require "yard"
require "yard/rake/yardoc_task"

YARD::Rake::YardocTask.new do |yard|
  # keeping this in here for now, but code can be deleted once we are ready
  # to push. .yardopts takes care of this.
  # yard.files = [
  #   "lib/sidekiq/api.rb",
  #   "lib/sidekiq/client.rb",
  #   "lib/sidekiq/worker.rb",
  #   # "lib/sidekiq/job.rb",
  #   "-",
  #   "Changes.md",
  #   "docs/menu.md"]
end

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
