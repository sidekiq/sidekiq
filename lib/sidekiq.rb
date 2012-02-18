require 'sidekiq/version'
require 'sidekiq/client'
require 'sidekiq/worker'
require 'sidekiq/rails' if defined?(::Rails)

require 'sidekiq/extensions/action_mailer'
require 'sidekiq/extensions/active_record'

module Sidekiq
  def self.redis
    @redis ||= Sidekiq::RedisConnection.create
  end
  def self.redis=(r)
    @redis = r
  end
end
