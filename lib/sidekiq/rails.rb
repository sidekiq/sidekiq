# frozen_string_literal: true

require "sidekiq/job"

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
        include ::Sidekiq::Job::Options unless respond_to?(:sidekiq_options)
      end
    end

    initializer "sidekiq.rails_logger" do
      Sidekiq.configure_server do |config|
        # This is the integration code necessary so that if a job uses `Rails.logger.info "Hello"`,
        # it will appear in the Sidekiq console with all of the job context. See #5021 and
        # https://github.com/rails/rails/blob/b5f2b550f69a99336482739000c58e4e04e033aa/railties/lib/rails/commands/server/server_command.rb#L82-L84
        unless ::Rails.logger == config.logger || ::ActiveSupport::Logger.logger_outputs_to?(::Rails.logger, $stdout)
          ::Rails.logger.extend(::ActiveSupport::Logger.broadcast(config.logger))
        end
      end
    end

    config.before_configuration do
      dep = ActiveSupport::Deprecation.new("7.0", "Sidekiq")
      dep.deprecate_methods(Sidekiq.singleton_class,
        default_worker_options: :default_job_options,
        "default_worker_options=": :default_job_options=)
    end

    # This hook happens after all initializers are run, just before returning
    # from config/environment.rb back to sidekiq/cli.rb.
    #
    # None of this matters on the client-side, only within the Sidekiq process itself.
    config.after_initialize do
      Sidekiq.configure_server do |config|
        config[:reloader] = Sidekiq::Rails::Reloader.new
      end
    end
  end
end
