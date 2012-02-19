require 'sidekiq/version'
require 'sidekiq/client'
require 'sidekiq/worker'
require 'sidekiq/rails' if defined?(::Rails)
require 'sidekiq/redis_connection'

require 'sidekiq/extensions/action_mailer'
require 'sidekiq/extensions/active_record'

require 'sidekiq/middleware/chain'
require 'sidekiq/middleware/server/active_record'
require 'sidekiq/middleware/server/airbrake'
require 'sidekiq/middleware/server/unique_jobs'
require 'sidekiq/middleware/server/failure_jobs'
require 'sidekiq/middleware/client/resque_web_compatibility'
require 'sidekiq/middleware/client/unique_jobs'

module Sidekiq

  def self.redis
    @redis ||= Sidekiq::RedisConnection.create
  end

  def self.redis=(r)
    @redis = r
  end

  def self.client_middleware
    @client_chain ||= begin
      m = Middleware::Chain.new
      m.add Middleware::Client::UniqueJobs
      m.add Middleware::Client::ResqueWebCompatibility
      m
    end
    yield @client_chain if block_given?
    @client_chain
  end

  def self.server_middleware
    @server_chain ||= begin
      m = Middleware::Chain.new
      m.add Middleware::Server::Airbrake
      m.add Middleware::Server::UniqueJobs
      m.add Middleware::Server::ActiveRecord
      m
    end

    yield @server_chain if block_given?
    @server_chain
  end

end
