# frozen_string_literal: true

require "sidekiq/version"
fail "Sidekiq #{Sidekiq::VERSION} does not support Ruby versions below 2.7.0." if RUBY_PLATFORM != "java" && Gem::Version.new(RUBY_VERSION) < Gem::Version.new("2.7.0")

require "sidekiq/config"
require "sidekiq/logger"
require "sidekiq/client"
require "sidekiq/transaction_aware_client"
require "sidekiq/job"
require "sidekiq/worker_compatibility_alias"
require "sidekiq/redis_client_adapter"

require "json"

module Sidekiq
  NAME = "Sidekiq"
  LICENSE = "See LICENSE and the LGPL-3.0 for licensing details."

  def self.❨╯°□°❩╯︵┻━┻
    puts "Take a deep breath and count to ten..."
  end

  def self.server?
    defined?(Sidekiq::CLI)
  end

  def self.load_json(string)
    JSON.parse(string)
  end

  def self.dump_json(object)
    JSON.generate(object)
  end

  def self.pro?
    defined?(Sidekiq::Pro)
  end

  def self.ent?
    defined?(Sidekiq::Enterprise)
  end

  def self.redis_pool
    (Thread.current[:sidekiq_capsule] || default_configuration).redis_pool
  end

  def self.redis(&block)
    (Thread.current[:sidekiq_capsule] || default_configuration).redis(&block)
  end

  def self.strict_args!(mode = :raise)
    Sidekiq::Config::DEFAULTS[:on_complex_arguments] = mode
  end

  def self.default_job_options=(hash)
    @default_job_options = default_job_options.merge(hash.transform_keys(&:to_s))
  end

  def self.default_job_options
    @default_job_options ||= {"retry" => true, "queue" => "default"}
  end

  def self.default_configuration
    @config ||= Sidekiq::Config.new
  end

  def self.configure_server
    yield default_configuration if server?
  end

  def self.configure_client
    yield default_configuration unless server?
  end

  # We are shutting down Sidekiq but what about threads that
  # are working on some long job?  This error is
  # raised in jobs that have not finished within the hard
  # timeout limit.  This is needed to rollback db transactions,
  # otherwise Ruby's Thread#kill will commit.  See #377.
  # DO NOT RESCUE THIS ERROR IN YOUR JOBS
  class Shutdown < Interrupt; end
end

require "sidekiq/rails" if defined?(::Rails::Engine)
