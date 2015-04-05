# encoding: utf-8
require 'sidekiq/version'
fail "Sidekiq #{Sidekiq::VERSION} does not support Ruby 1.9." if RUBY_PLATFORM != 'java' && RUBY_VERSION < '2.0.0'

require 'sidekiq/logging'
require 'sidekiq/client'
require 'sidekiq/worker'
require 'sidekiq/redis_connection'

require 'json'

module Sidekiq
  NAME = 'Sidekiq'
  LICENSE = 'See LICENSE and the LGPL-3.0 for licensing details.'

  DEFAULTS = {
    queues: [],
    labels: [],
    concurrency: 25,
    require: '.',
    environment: nil,
    timeout: 8,
    error_handlers: [],
    lifecycle_events: {
      startup: [],
      quiet: [],
      shutdown: [],
    },
    dead_max_jobs: 10_000,
    dead_timeout_in_seconds: 180 * 24 * 60 * 60 # 6 months
  }

  DEFAULT_WORKER_OPTIONS = {
    'retry' => true,
    'queue' => 'default'
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
    raise ArgumentError, "requires a block" unless block
    redis_pool.with(&block)
  end

  def self.redis_pool
    @redis ||= Sidekiq::RedisConnection.create
  end

  def self.redis=(hash)
    @redis = if hash.is_a?(ConnectionPool)
      hash
    else
      Sidekiq::RedisConnection.create(hash)
    end
  end

  def self.client_middleware
    @client_chain ||= Middleware::Chain.new
    yield @client_chain if block_given?
    @client_chain
  end

  def self.server_middleware
    @server_chain ||= Processor.default_middleware
    yield @server_chain if block_given?
    @server_chain
  end

  def self.default_worker_options=(hash)
    @default_worker_options = default_worker_options.merge(hash.stringify_keys)
  end

  def self.default_worker_options
    defined?(@default_worker_options) ? @default_worker_options : DEFAULT_WORKER_OPTIONS
  end

  def self.load_json(string)
    JSON.parse(string)
  end

  def self.dump_json(object)
    JSON.generate(object)
  end

  def self.logger
    Sidekiq::Logging.logger
  end

  def self.logger=(log)
    Sidekiq::Logging.logger = log
  end

  # See sidekiq/scheduled.rb for an in-depth explanation of this value
  def self.poll_interval=(interval)
    self.options[:poll_interval] = interval
  end

  # Register a proc to handle any error which occurs within the Sidekiq process.
  #
  #   Sidekiq.configure_server do |config|
  #     config.error_handlers << Proc.new {|ex,ctx_hash| MyErrorService.notify(ex, ctx_hash) }
  #   end
  #
  # The default error handler logs errors to Sidekiq.logger.
  def self.error_handlers
    self.options[:error_handlers]
  end

  # Register a block to run at a point in the Sidekiq lifecycle.
  # :startup, :quiet or :shutdown are valid events.
  #
  #   Sidekiq.configure_server do |config|
  #     config.on(:shutdown) do
  #       puts "Goodbye cruel world!"
  #     end
  #   end
  def self.on(event, &block)
    raise ArgumentError, "Symbols only please: #{event}" unless event.is_a?(Symbol)
    raise ArgumentError, "Invalid event name: #{event}" unless options[:lifecycle_events].key?(event)
    options[:lifecycle_events][event] << block
  end
end

require 'sidekiq/extensions/class_methods'
require 'sidekiq/extensions/action_mailer'
require 'sidekiq/extensions/active_record'
require 'sidekiq/rails' if defined?(::Rails::Engine)
