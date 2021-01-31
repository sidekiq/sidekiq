# frozen_string_literal: true

require "erb"

require "sidekiq"
require "sidekiq/api"
require "sidekiq/paginator"
require "sidekiq/web/helpers"

require "sidekiq/web/router"
require "sidekiq/web/action"
require "sidekiq/web/application"
require "sidekiq/web/csrf_protection"

require "rack/content_length"

require "rack/builder"
require "rack/file"
require "rack/session/cookie"

module Sidekiq
  class Web
    ROOT = File.expand_path("#{File.dirname(__FILE__)}/../../web")
    VIEWS = "#{ROOT}/views"
    LOCALES = ["#{ROOT}/locales"]
    LAYOUT = "#{VIEWS}/layout.erb"
    ASSETS = "#{ROOT}/assets"

    DEFAULT_TABS = {
      "Dashboard" => "",
      "Busy" => "busy",
      "Queues" => "queues",
      "Retries" => "retries",
      "Scheduled" => "scheduled",
      "Dead" => "morgue"
    }

    class << self
      def settings
        self
      end

      def middlewares
        @middlewares ||= []
      end

      def use(*middleware_args, &block)
        middlewares << [middleware_args, block]
      end

      def default_tabs
        DEFAULT_TABS
      end

      def custom_tabs
        @custom_tabs ||= {}
      end
      alias_method :tabs, :custom_tabs

      def locales
        @locales ||= LOCALES
      end

      def views
        @views ||= VIEWS
      end

      def enable(*opts)
        opts.each { |key| set(key, true) }
      end

      def disable(*opts)
        opts.each { |key| set(key, false) }
      end

      # Helper for the Sinatra syntax: Sidekiq::Web.set(:session_secret, Rails.application.secrets...)
      def set(attribute, value)
        send(:"#{attribute}=", value)
      end

      def sessions=(val)
        raise <<~EOM
          Warning: disabling sessions opens your Sidekiq UI up to CSRF attacks. You may
          disable them by setting `SIDEKIQ_DISABLE_SESSIONS_THIS_IS_A_BAD_IDEA=true`.
        EOM
      end

      def session_secret=(val)
        raise <<~EOM
          Sidekiq no longer allows setting the session secret directly. Either configure
          your session middleware directly or allow Sidekiq to reuse the Rails session.
        EOM
      end

      attr_accessor :app_url, :redis_pool
      attr_writer :locales, :views
    end

    def self.inherited(child)
      child.app_url = app_url
      child.redis_pool = redis_pool
    end

    def settings
      self.class.settings
    end

    def use(*middleware_args, &block)
      middlewares << [middleware_args, block]
    end

    def middlewares
      @middlewares ||= Web.middlewares.dup
    end

    def call(env)
      app.call(env)
    end

    def self.call(env)
      @app ||= new
      @app.call(env)
    end

    def app
      @app ||= build
    end

    def enable(*opts)
      opts.each { |key| set(key, true) }
    end

    def disable(*opts)
      opts.each { |key| set(key, false) }
    end

    def set(attribute, value)
      send(:"#{attribute}=", value)
    end

    def sessions=(val)
      raise <<~EOM
        Sidekiq no longer allows configuring the session via Sidekiq::Web. Either configure
        your session middleware directly or allow Sidekiq to reuse the Rails session.
      EOM
    end

    def self.register(extension)
      extension.registered(WebApplication)
    end

    private

    def using?(middleware)
      middlewares.any? do |(m, _)|
        m.is_a?(Array) && (m[0] == middleware || m[0].is_a?(middleware))
      end
    end

    def build_sessions
      disable_sessions = ENV["SIDEKIQ_DISABLE_SESSIONS_THIS_IS_A_BAD_IDEA"] == "true" || ENV["RACK_ENV"] == "test"

      # turn on CSRF protection if sessions are enabled and this is not the test env
      unless disable_sessions || using?(CsrfProtection)
        middlewares.unshift [[CsrfProtection], nil]
      end
    end

    def build
      build_sessions

      middlewares = self.middlewares
      klass = self.class

      ::Rack::Builder.new do
        %w[stylesheets javascripts images].each do |asset_dir|
          map "/#{asset_dir}" do
            run ::Rack::File.new("#{ASSETS}/#{asset_dir}", {"Cache-Control" => "public, max-age=86400"})
          end
        end

        middlewares.each { |middleware, block| use(*middleware, &block) }

        run WebApplication.new(klass)
      end
    end
  end

  Sidekiq::WebApplication.helpers WebHelpers
  Sidekiq::WebApplication.helpers Sidekiq::Paginator

  Sidekiq::WebAction.class_eval <<-RUBY, __FILE__, __LINE__ + 1
    def _render
      #{ERB.new(File.read(Web::LAYOUT)).src}
    end
  RUBY
end
