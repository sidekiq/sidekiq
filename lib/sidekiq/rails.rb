# frozen_string_literal: true

require "sidekiq/worker"

module Sidekiq
  class Rails < ::Rails::Engine
    class Reloader
      def initialize(app = ::Rails.application)
        @app = app
      end

      def call
        @app.reloader.wrap do
          yield
        end
      end

      def inspect
        "#<Sidekiq::Rails::Reloader @app=#{@app.class.name}>"
      end
    end

    # By including the Options module, we allow AJs to directly control sidekiq features
    # via the *sidekiq_options* class method and, for instance, not use AJ's retry system.
    # AJ retries don't show up in the Sidekiq UI Retries tab, save any error data, can't be
    # manually retried, don't automatically die, etc.
    #
    #   class SomeJob < ActiveJob::Base
    #     queue_as :default
    #     sidekiq_options retry: 3, backtrace: 10
    #     def perform
    #     end
    #   end
    initializer "sidekiq.active_job_integration" do
      ActiveSupport.on_load(:active_job) do
        include ::Sidekiq::Worker::Options unless respond_to?(:sidekiq_options)
      end
    end

    # This hook happens after all initializers are run, just before returning
    # from config/environment.rb back to sidekiq/cli.rb.
    #
    # None of this matters on the client-side, only within the Sidekiq process itself.
    config.after_initialize do
      Sidekiq.configure_server do |_|
        Sidekiq.options[:reloader] = Sidekiq::Rails::Reloader.new
      end
    end
  end
end
