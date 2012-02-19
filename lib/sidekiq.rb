require 'sidekiq/version'
require 'sidekiq/client'
require 'sidekiq/worker'
require 'sidekiq/rails' if defined?(::Rails)
require 'sidekiq/redis_connection'

require 'sidekiq/extensions/action_mailer' if defined?(::ActionMailer)
require 'sidekiq/extensions/active_record' if defined?(::ActiveRecord)

module Sidekiq

  DEFAULTS = {
    :queues => [],
    :concurrency => 25,
    :require => '.',
    :environment => nil,
  }

  def self.options
    @options ||= DEFAULTS.dup
  end

  def self.options=(opts)
    @options = opts
  end

  ##
  # Configuration for Sidekiq, use like:
  #
  #   Sidekiq.configure do |config|
  #     config.server_middleware do |chain|
  #       chain.add MyServerHook
  #     end
  #   end
  def self.configure
    yield self
  end

  def self.redis
    @redis ||= Sidekiq::RedisConnection.create
  end

  def self.redis=(r)
    @redis = r
  end

  def self.client_middleware
    @client_chain ||= Client.default_middleware
    yield @client_chain if block_given?
    @client_chain
  end

  def self.server_middleware
    @server_chain ||= Processor.default_middleware
    yield @server_chain if block_given?
    @server_chain
  end

end
