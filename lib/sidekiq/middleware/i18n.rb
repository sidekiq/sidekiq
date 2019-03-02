# frozen_string_literal: true

#
# Simple middleware to save the current locale and restore it when the job executes.
# Use it by requiring it in your initializer:
#
#     require 'sidekiq/middleware/i18n'
#
module Sidekiq::Middleware::I18n
  # Get the current locale and store it in the message
  # to be sent to Sidekiq.
  class Client
    def call(_worker, msg, _queue, _redis)
      msg["locale"] ||= I18n.locale
      yield
    end
  end

  # Pull the msg locale out and set the current thread to use it.
  class Server
    def call(_worker, msg, _queue, &block)
      I18n.with_locale(msg.fetch("locale", I18n.default_locale), &block)
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
