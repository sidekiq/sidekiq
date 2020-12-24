# frozen_string_literal: true

require "sidekiq/version"
fail "Sidekiq #{Sidekiq::VERSION} does not support Ruby versions below 2.7.0." if RUBY_PLATFORM != "java" && Gem::Version.new(RUBY_VERSION) < Gem::Version.new("2.7.0")

require "sidekiq/client"
require "sidekiq/worker"
require "sidekiq/configuration"

require "json"

module Sidekiq
  NAME = "Sidekiq"
  LICENSE = "See LICENSE and the LGPL-3.0 for licensing details."

  DEFAULTS = {
    dead_max_jobs: 10_000,
    dead_timeout_in_seconds: 180 * 24 * 60 * 60, # 6 months
  }

  ##
  # Configuration for the Sidekiq job runner, use like:
  #
  #   Sidekiq.configure_server do |config|
  #     config.concurrency = 5
  #     config.server_middleware do |chain|
  #       chain.add MyServerHook
  #     end
  #   end
  def self.configure_server
    yield Sidekiq::CLI.instance.configuration if server?
  end

  ##
  # Configuration for Sidekiq client, use like:
  #
  #   Sidekiq.configure_client do |config|
  #   end
  def self.configure_client
    yield self unless server?
  end

  def self.configure
    yield DEFAULT_CONFIG
    DEFAULT_CONFIG.freeze!

    if server?
      Sidekiq::CLI.instance.apply(DEFAULT_CONFIG)
    else
      Sidekiq::Client.apply(DEFAULT_CONFIG)
    end
  end

  def self.server?
    defined?(Sidekiq::CLI)
  end

  def self.redis
    raise ArgumentError, "requires a block" unless block_given?
    redis_pool.with do |conn|
      retryable = true
      begin
        yield conn
      rescue Redis::BaseError => ex
        # 2550 Failover can cause the server to become a replica, need
        # to disconnect and reopen the socket to get back to the primary.
        # 4495 Use the same logic if we have a "Not enough replicas" error from the primary
        if retryable && ex.message =~ /READONLY|NOREPLICAS/
          conn.disconnect!
          retryable = false
          retry
        end
        raise
      end
    end
  end

  def self.redis_info
    redis do |conn|
      # admin commands can't go through redis-namespace starting
      # in redis-namespace 2.0
      if conn.respond_to?(:namespace)
        conn.redis.info
      else
        conn.info
      end
    rescue Redis::CommandError => ex
      # 2850 return fake version when INFO command has (probably) been renamed
      raise unless /unknown command/.match?(ex.message)
      FAKE_INFO
    end
  end

  def self.load_json(string)
    JSON.parse(string)
  end

  def self.dump_json(object)
    JSON.generate(object)
  end

  def self.log_formatter
    @log_formatter ||= if ENV["DYNO"]
      Sidekiq::Logger::Formatters::WithoutTimestamp.new
    else
      Sidekiq::Logger::Formatters::Pretty.new
    end
  end

  def self.log_formatter=(log_formatter)
    @log_formatter = log_formatter
    logger.formatter = log_formatter
  end

  def self.logger=(logger)
    if logger.nil?
      self.logger.level = Logger::FATAL
      return self.logger
    end

    logger.extend(Sidekiq::LoggingUtils)

    @logger = logger
  end

  def self.pro?
    defined?(Sidekiq::Pro)
  end

  # We are shutting down Sidekiq but what about workers that
  # are working on some long job?  This error is
  # raised in workers that have not finished within the hard
  # timeout limit.  This is needed to rollback db transactions,
  # otherwise Ruby's Thread#kill will commit.  See #377.
  # DO NOT RESCUE THIS ERROR IN YOUR WORKERS
  class Shutdown < Interrupt; end
end

require "sidekiq/rails" if defined?(::Rails::Engine)
