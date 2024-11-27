# frozen_string_literal: true

require "erb"
require "securerandom"
require "rack/builder"
require "rack/static"
require "sidekiq"
require "sidekiq/api"

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
      "Dead" => "morgue",
      "Metrics" => "metrics",
      "Profiles" => "profiles"
    }

    # By default we support direct uploads to p.f.c since the UI is a JS SPA
    # and very difficult for us to vendor or provide ourselves. If you are worried
    # about data security and wish to self-host, you can change these URLs.
    PROFILE_OPTIONS = {
      view_url: "https://profiler.firefox.com/public/%s",
      store_url: "https://api.profiler.firefox.com/compressed-store"
    }

    class << self
      def tabs
        @tabs ||= DEFAULT_TABS.dup
      end

      def locales
        @locales ||= LOCALES
      end

      def views
        @views ||= VIEWS
      end

      def redis_pool
        @pool || Sidekiq.default_configuration.redis_pool
      end

      def redis_pool=(pool)
        @pool = pool
      end

      def middlewares
        @middlewares ||= []
      end

      def use(*args, &block)
        middlewares << [args, block]
      end
      attr_accessor :app_url
    end

    # def use(*args, &) = self.class.use(*args, &)

    # def middlewares = self.class.middlewares

    # Allow user to say
    #   run Sidekiq::Web
    # rather than:
    #   run Sidekiq::Web.new
    def self.call(env)
      @inst ||= new
      @inst.call(env)
    end

    def call(env)
      env[:csp_nonce] = SecureRandom.base64(16)
      env[:redis_pool] = self.class.redis_pool
      app.call(env)
    end

    def app
      @app ||= build
    end

    # Register a class as a Sidekiq Web UI extension. The class should
    # provide one or more tabs which map to an index route. Options:
    #
    # @param extension [Class] Class which contains the HTTP actions, required
    # @param name [String] the name of the extension, used to namespace assets
    # @param tab [String | Array] labels(s) of the UI tabs
    # @param index [String | Array] index route(s) for each tab
    # @param root_dir [String] directory location to find assets, locales and views, typically `web/` within the gemfile
    # @param asset_paths [Array] one or more directories under {root}/assets/{name} to be publicly served, e.g. ["js", "css", "img"]
    # @param cache_for [Integer] amount of time to cache assets, default one day
    #
    # Web extensions will have a root `web/` directory with `locales/`, `assets/`
    # and `views/` subdirectories.
    def self.register(extension, name:, tab:, index:, root_dir: nil, cache_for: 86400, asset_paths: nil)
      tab = Array(tab)
      index = Array(index)
      tab.zip(index).each do |tab, index|
        tabs[tab] = index
      end
      if root_dir
        locdir = File.join(root_dir, "locales")
        locales << locdir if File.directory?(locdir)

        if asset_paths && name
          # if you have {root}/assets/{name}/js/scripts.js
          # and {root}/assets/{name}/css/styles.css
          # you would pass in:
          #   asset_paths: ["js", "css"]
          # See script_tag and style_tag in web/helpers.rb
          assdir = File.join(root_dir, "assets")
          assurls = Array(asset_paths).map { |x| "/#{name}/#{x}" }
          assetprops = {
            urls: assurls,
            root: assdir,
            cascade: true
          }
          assetprops[:header_rules] = [[:all, {"cache-control" => "private, max-age=#{cache_for.to_i}"}]] if cache_for
          middlewares << [[Rack::Static, assetprops], nil]
        end
      end

      yield self if block_given?
      extension.registered(Web::Application)
    end

    private

    def build
      klass = self.class
      m = klass.middlewares

      rules = []
      rules = [[:all, {"cache-control" => "private, max-age=86400"}]] unless ENV["SIDEKIQ_WEB_TESTING"]

      ::Rack::Builder.new do
        use Rack::Static, urls: ["/stylesheets", "/images", "/javascripts"],
          root: ASSETS,
          cascade: true,
          header_rules: rules
        m.each { |middleware, block| use(*middleware, &block) }
        use Sidekiq::Web::CsrfProtection unless $TESTING
        run Sidekiq::Web::Application.new(klass)
      end
    end
  end
end

require "sidekiq/web/router"
require "sidekiq/web/action"
require "sidekiq/web/application"
require "sidekiq/web/csrf_protection"
