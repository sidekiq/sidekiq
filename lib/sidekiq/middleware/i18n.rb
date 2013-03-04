module Sidekiq::Middleware::I18n
  # Get the current locale and store it in the message
  # to be sent to Sidekiq.
  class Client
    def call(worker_class, msg, queue)
      msg['locale'] = I18n.locale
      yield
    end
  end

  # Pull the msg locale out and set the current thread to use it.
  class Server
    def call(worker, msg, queue)
      I18n.locale = msg['locale'] || I18n.default_locale
      yield
    ensure
      I18n.locale = nil
    end
  end
end

Sidekiq.configure_client do |config|
  config.client_middleware do |chain|
    chain.add Sidekiq::Middleware::I18n::Client
  end
end

Sidekiq.configure_server do |config|
  config.client_middleware do |chain|
    chain.add Sidekiq::Middleware::I18n::Client
  end
  config.server_middleware do |chain|
    chain.add Sidekiq::Middleware::I18n::Server
  end
end
