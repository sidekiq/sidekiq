# Making sure we do not leak memory

require 'sidekiq'

redis = { :namespace => 'leak' }
Sidekiq.configure_client { |config| config.redis = redis }
Sidekiq.configure_server { |config| config.redis = redis }

$c = 0
$max = 10_000

# Start up sidekiq via
# ./bin/sidekiq -r ./examples/leak.rb > /dev/null
class MyWorker
  include Sidekiq::Worker

  def perform
    $c += 1
    if $c % 100 == 0
      GC.start
      memory = `ps -o rss -p #{Process.pid}`.chomp.split("\n").last.to_i
      $stderr.puts "Using memory #{memory}"
    end
    if $c >= $max
      exit
    end
  end
end

# schedule some jobs to work on
$max.times { MyWorker.perform_async }
