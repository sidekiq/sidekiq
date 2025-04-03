# frozen_string_literal: true

require "sidekiq/job"

module Sidekiq
  if defined?(::ActiveJob)
    # By including the Options module, we allow AJs to directly control sidekiq features
    # via the *sidekiq_options* class method and, for instance, not use AJ's retry system.
    # AJ retries don't show up in the Sidekiq UI Retries tab, don't save any error data, can't be
    # manually retried, don't automatically die, etc.
    #
    #   class SomeJob < ActiveJob::Base
    #     queue_as :default
    #     sidekiq_options retry: 3, backtrace: 10
    #     def perform
    #     end
    #   end
    require_relative "../active_job/queue_adapters/sidekiq_adapter"
    ::ActiveJob::Base.include ::Sidekiq::Job::Options unless ::ActiveJob::Base.respond_to?(:sidekiq_options)
    module ActiveJob
      # @api private
      class Wrapper
        include Sidekiq::Job

        def perform(job_data)
          ::ActiveJob::Base.execute(job_data.merge("provider_job_id" => jid))
        end
      end
    end
  end

  if defined?(::Rails::Engine)
    class Rails < ::Rails::Engine
      class Reloader
        def initialize(app = ::Rails.application)
          @app = app
        end

        def call
          params = (::Rails::VERSION::STRING >= "7.1") ? { source: "job.sidekiq" } : {}
          @app.reloader.wrap(**params) do
            yield
          end
        end

        def inspect
          "#<Sidekiq::Rails::Reloader @app=#{@app.class.name}>"
        end

        def to_hash
          { app: @app.class.name }
        end
      end

      initializer "sidekiq.backtrace_cleaner" do
        Sidekiq.configure_server do |config|
          config[:backtrace_cleaner] = ->(backtrace) { ::Rails.backtrace_cleaner.clean(backtrace) }
        end
      end

      # This hook happens after all initializers are run, just before returning
      # from config/environment.rb back to sidekiq/cli.rb.
      #
      # None of this matters on the client-side, only within the Sidekiq process itself.
      config.after_initialize do
        Sidekiq.configure_server do |config|
          config[:reloader] = Sidekiq::Rails::Reloader.new

          # This is the integration code necessary so that if a job uses `Rails.logger.info "Hello"`,
          # it will appear in the Sidekiq console with all of the job context.
          unless ::Rails.logger == config.logger || ::ActiveSupport::Logger.logger_outputs_to?(::Rails.logger, $stdout)
            if ::Rails.logger.respond_to?(:broadcast_to)
              ::Rails.logger.broadcast_to(config.logger)
            else
              ::Rails.logger.extend(::ActiveSupport::Logger.broadcast(config.logger))
            end
          end
        end
      end
    end
  end
end
