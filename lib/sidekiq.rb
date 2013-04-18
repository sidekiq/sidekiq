# encoding: utf-8
require 'sidekiq/version'
require 'sidekiq/logging'
require 'sidekiq/client'
require 'sidekiq/worker'
require 'sidekiq/redis_connection'
require 'sidekiq/util'
require 'sidekiq/api'

require 'multi_json'

module Sidekiq
  NAME = "Sidekiq"
  LICENSE = 'See LICENSE and the LGPL-3.0 for licensing details.'

  DEFAULTS = {
    :queues => [],
    :concurrency => 25,
    :require => '.',
    :environment => nil,
    :timeout => 8,
    :profile => false,
  }

  def self.❨╯°□°❩╯︵┻━┻
    puts "Calm down, bro"
  end

  def self.options
    @options ||= DEFAULTS.dup
  end

  def self.options=(opts)
    @options = opts
  end

  ##
  # Configuration for Sidekiq server, use like:
  #
  #   Sidekiq.configure_server do |config|
  #     config.redis = { :namespace => 'myapp', :size => 25, :url => 'redis://myhost:8877/0' }
  #     config.server_middleware do |chain|
  #       chain.add MyServerHook
  #     end
  #   end
  def self.configure_server
    yield self if server?
  end

  ##
  # Configuration for Sidekiq client, use like:
  #
  #   Sidekiq.configure_client do |config|
  #     config.redis = { :namespace => 'myapp', :size => 1, :url => 'redis://myhost:8877/0' }
  #   end
  def self.configure_client
    yield self unless server?
  end

  def self.server?
    defined?(Sidekiq::CLI)
  end

  def self.redis(&block)
    raise ArgumentError, "requires a block" if !block
    @redis ||= Sidekiq::RedisConnection.create(@hash || {})
    @redis.with(&block)
  end

  def self.redis=(hash)
    return @redis = hash if hash.is_a?(ConnectionPool)

    if hash.is_a?(Hash)
      @hash = hash
    else
      raise ArgumentError, "redis= requires a Hash or ConnectionPool"
    end
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

  def self.load_json(string)
    MultiJson.decode(string, :symbolize_keys => false)
  end

  def self.dump_json(object)
    MultiJson.encode(object)
  end

  def self.logger
    Sidekiq::Logging.logger
  end

  def self.logger=(log)
    Sidekiq::Logging.logger = log
  end

  def self.poll_interval=(interval)
    self.options[:poll_interval] = interval
  end

end

require 'sidekiq/extensions/class_methods'
require 'sidekiq/extensions/action_mailer'
require 'sidekiq/extensions/active_record'
require 'sidekiq/rails' if defined?(::Rails::Engine)

