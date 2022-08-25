Sidekiq.default_job_options = {queue: "something"}
Sidekiq.configure_client do |config|
  config.redis = {size: 2}
end
Sidekiq.configure_server do |config|
  config.on(:startup) {}
  config.on(:quiet) {}
  config.on(:shutdown) do
    # result = RubyProf.stop

    ## Write the results to a file
    ## Requires railsexpress patched MRI build
    # brew install qcachegrind
    # File.open("callgrind.profile", "w") do |f|
    # RubyProf::CallTreePrinter.new(result).print(f, :min_percent => 1)
    # end
  end
end

class EmptyWorker
  include Sidekiq::Worker

  def perform
  end
end

class TimedWorker
  include Sidekiq::Worker

  def perform(start)
    now = Time.now.to_f
    puts "Latency: #{now - start} sec"
  end
end

module Myapp
  class Current < ActiveSupport::CurrentAttributes
    attribute :tenant_id
  end
end

require "sidekiq/middleware/current_attributes"
Sidekiq::CurrentAttributes.persist(Myapp::Current) # Your AS::CurrentAttributes singleton

# Sidekiq.transactional_push!

# create a label based on the shorthash and subject line of the latest commit in git.
# WARNING: you only want to run this ONCE! If this runs on boot for 20 different Sidekiq processes,
# you will get 20 different deploy marks in Redis! Instead this should go into the script
# that runs your deploy, e.g. your capistrano script.
Sidekiq.configure_server do |config|
  label = `git log -1 --format="%h %s"`.strip
  require "sidekiq/metrics/deploy"
  Sidekiq::Metrics::Deploy.new.mark(label: label)
end

class Singler
  include Sidekiq::ServerMiddleware
  def call(w, j, q)
    puts q
  end
end

Sidekiq.configure_server do |config|
  config.capsule("single_threaded") do |cap|
    cap.concurrency = 1
    cap.queues = %w[single default]
    cap.server_middleware.add Singler
  end
end

# helper jobs for seeding metrics data
# you will need to restart if you change any of these
class FooJob
  include Sidekiq::Job
  def perform(*)
    raise "boom" if rand < 0.1
    sleep(rand)
  end
end

class BarJob
  include Sidekiq::Job
  def perform(*)
    raise "boom" if rand < 0.1
    sleep(rand)
  end
end

class StoreCardJob
  include Sidekiq::Job
  def perform(*)
    raise "boom" if rand < 0.1
    sleep(rand)
  end
end

class OrderJunkJob
  include Sidekiq::Job
  def perform(*)
    raise "boom" if rand < 0.1
    sleep(rand)
  end
end

class SpamUserJob
  include Sidekiq::Job
  def perform(*)
    raise "boom" if rand < 0.1
    sleep(rand)
  end
end

class FastJob
  include Sidekiq::Job
  def perform(*)
    raise "boom" if rand < 0.2
    sleep(rand * 0.1)
  end
end

class SlowJob
  include Sidekiq::Job
  def perform(*)
    raise "boom" if rand < 0.3
    sleep(rand * 10)
  end
end
