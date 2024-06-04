module Sidekiq
  module Job
    class InterruptHandler
      include Sidekiq::ServerMiddleware

      def call(instance, hash, queue)
        yield
      rescue Interrupted
        backoff = 30
        c = Sidekiq::Client.new
        c.push(hash.merge("at" => (Time.now + backoff).to_f))
      end
    end
  end
end

Sidekiq.configure_server do |config|
  config.server_middleware do |chain|
    chain.add Sidekiq::Job::InterruptHandler
  end
end
