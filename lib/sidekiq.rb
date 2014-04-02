# encoding: utf-8
require 'sidekiq/version'
require 'sidekiq/logging'
require 'sidekiq/client'
require 'sidekiq/worker'
require 'sidekiq/redis_connection'

require 'json'

module Sidekiq
  NAME = "Sidekiq"
  LICENSE = 'See LICENSE and the LGPL-3.0 for licensing details.'

  DEFAULTS = {
    :queues => [],
    :concurrency => 25,
    :require => '.',
    :environment => nil,
    :timeout => 8,
    :error_handlers => [],
    :lifecycle_events => {
      :startup => [],
      :quiet => [],
      :shutdown => [],
    },
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
    @default_worker_options = default_worker_options.merge(hash)
  end

  def self.default_worker_options
    defined?(@default_worker_options) ? @default_worker_options : { 'retry' => true, 'queue' => 'default' }
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

  # The default poll interval is 15 seconds.  This should generally be set to
  # (Sidekiq process count * 5).  So if you have a dozen Sidekiq processes, set
  # poll_interval to 60.
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
    raise ArgumentError, "Symbols only please: #{event}" if !event.is_a?(Symbol)
    raise ArgumentError, "Invalid event name: #{event}" if !options[:lifecycle_events].keys.include?(event)
    options[:lifecycle_events][event] << block
  end

  BANNER = %q{         s
        ss
   sss  sss         ss
   s  sss s   ssss sss   ____  _     _      _    _
   s     sssss ssss     / ___|(_) __| | ___| | _(_) __ _
  s         sss         \___ \| |/ _` |/ _ \ |/ / |/ _` |
  s sssss  s             ___) | | (_| |  __/   <| | (_| |
  ss    s  s            |____/|_|\__,_|\___|_|\_\_|\__, |
  s     s s                                           |_|
        s s
       sss
       sss }

end

require 'sidekiq/extensions/class_methods'
require 'sidekiq/extensions/action_mailer'
require 'sidekiq/extensions/active_record'
require 'sidekiq/rails' if defined?(::Rails::Engine)
