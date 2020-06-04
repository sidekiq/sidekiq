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

      attr_accessor :app_url, :session_secret, :redis_pool, :sessions
      attr_writer :locales, :views
    end

    def self.inherited(child)
      child.app_url = app_url
      child.session_secret = session_secret
      child.redis_pool = redis_pool
      child.sessions = sessions
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

    # Default values
    set :sessions, true

    attr_writer :sessions

    def sessions
      unless instance_variable_defined?("@sessions")
        @sessions = self.class.sessions
        @sessions = @sessions.to_hash.dup if @sessions.respond_to?(:to_hash)
      end

      @sessions
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
      middlewares = self.middlewares

      s = sessions

      # turn on CSRF protection if sessions are enabled and this is not the test env
      if s && !using?(CsrfProtection) && ENV["RACK_ENV"] != "test"
        middlewares.unshift [[CsrfProtection], nil]
      end

      if s && !using?(::Rack::Session::Cookie)
        unless (secret = Web.session_secret)
          require "securerandom"
          secret = SecureRandom.hex(64)
        end

        options = {secret: secret}
        options = options.merge(s.to_hash) if s.respond_to? :to_hash

        middlewares.unshift [[::Rack::Session::Cookie, options], nil]
      end

      # Since Sidekiq::WebApplication no longer calculates its own
      # Content-Length response header, we must ensure that the Rack middleware
      # that does this is loaded
      unless using? ::Rack::ContentLength
        middlewares.unshift [[::Rack::ContentLength], nil]
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
