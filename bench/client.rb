require "benchmark/ips"
require "sidekiq"
require "active_job"

ActiveJob::Base.logger = nil
ActiveJob::Base.queue_adapter = :sidekiq

class MyJob
  include Sidekiq::Job
end

class AJob < ActiveJob::Base
  queue_as :default
end

Benchmark.ips do |x|
  x.hold! "bench.txt"
  x.report("Sidekiq::Job v7") do |times|
    i = 0
    while i < times
      MyJob.perform_async("foo", 123, {"mike" => true}, Time.now.to_f)
      i += 1
    end
  end
  x.report("ActiveJob v#{ActiveJob.version}") do |times|
    i = 0
    while i < times
      AJob.perform_later(:foo, 123, {mike: 0..5}, Time.now)
      i += 1
    end
  end
  x.report("Sidekiq::Job v8") do |times|
    Sidekiq::JSON.flavor!(:v8)
    i = 0
    while i < times
      MyJob.perform_async(:foo, 123, {"mike" => 0..5}, Time.now)
      i += 1
    end
  end
end

#
# Local results:
#
#      Sidekiq::Job v7     20.076k (± 1.2%) i/s -    100.940k in   5.028478s
#      Sidekiq::Job v8     19.177k (± 0.6%) i/s -     97.410k in   5.079620s
#   ActiveJob v7.0.8.1     11.793k (± 1.4%) i/s -     60.078k in   5.095490s
#
# Sidekiq's v8 flavor gets you support for many more Ruby types with
# almost no performance penalty.
