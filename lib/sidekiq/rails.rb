# frozen_string_literal: true
module Sidekiq
  def self.hook_rails!
    return if defined?(@delay_removed)

    ActiveSupport.on_load(:active_record) do
      include Sidekiq::Extensions::ActiveRecord
    end

    ActiveSupport.on_load(:action_mailer) do
      extend Sidekiq::Extensions::ActionMailer
    end

    Module.__send__(:include, Sidekiq::Extensions::Klass)
  end

  # Removes the generic aliases which MAY clash with names of already
  #  created methods by other applications. The methods `sidekiq_delay`,
  #  `sidekiq_delay_for` and `sidekiq_delay_until` can be used instead.
  def self.remove_delay!
    @delay_removed = true

    [Extensions::ActiveRecord,
     Extensions::ActionMailer,
     Extensions::Klass].each do |mod|
      mod.module_eval do
        remove_method :delay if respond_to?(:delay)
        remove_method :delay_for if respond_to?(:delay_for)
        remove_method :delay_until if respond_to?(:delay_until)
      end
    end
  end

  class Rails < ::Rails::Engine
    # We need to setup this up before any application configuration which might
    # change Sidekiq middleware.
    #
    # This hook happens after `Rails::Application` is inherited within
    # config/application.rb and before config is touched, usually within the
    # class block. Definitely before config/environments/*.rb and
    # config/initializers/*.rb.
    config.before_configuration do
      if ::Rails::VERSION::MAJOR < 5 && defined?(::ActiveRecord)
        Sidekiq.server_middleware do |chain|
          require 'sidekiq/middleware/server/active_record'
          chain.add Sidekiq::Middleware::Server::ActiveRecord
        end
      end
    end

    initializer 'sidekiq' do
      Sidekiq.hook_rails!
    end

    # We have to add the reloader after initialize to see if cache_classes has
    # been turned on.
    #
    # This hook happens after all initialziers are run, just before returning
    # from config/environment.rb back to sidekiq/cli.rb.
    config.after_initialize do
      if ::Rails::VERSION::MAJOR >= 5
        # The reloader also takes care of ActiveRecord but is incompatible with
        # the ActiveRecord middleware so make sure it's not in the chain already.
        if defined?(Sidekiq::Middleware::Server::ActiveRecord) && Sidekiq.server_middleware.exists?(Sidekiq::Middleware::Server::ActiveRecord)
          raise ArgumentError, "You are using the Sidekiq ActiveRecord middleware and the new Rails 5 reloader which are incompatible. Please remove the ActiveRecord middleware from your Sidekiq middleware configuration."
        elsif ::Rails.application.config.cache_classes
          # The reloader API has proven to be troublesome under load in production.
          # We won't use it at all when classes are cached, see #3154
          Sidekiq.logger.debug { "Autoload disabled in #{::Rails.env}, Sidekiq will not reload changed classes" }
        else
          Sidekiq.options[:reloader] = Sidekiq::Rails::Reloader.new
        end
      end
    end

    class Reloader
      def initialize(app = ::Rails.application)
        Sidekiq.logger.debug "Enabling Rails 5+ live code reloading, so hot!" unless app.config.cache_classes
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
  end if defined?(::Rails)
end
