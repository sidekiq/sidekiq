require "sidekiq/cli"
workers 3
threads 3, 5

on_worker_boot do
  $sidekiq = Sidekiq.configure_embed do |config|
    config.queues = %w[critical default low]
    # don't raise this unless you know your app has available CPU time to burn.
    # it's easy to overload a Ruby process with too many threads.
    config.concurrency = 2
  end
  $sidekiq&.run
end

on_worker_shutdown do
  $sidekiq&.stop
end
