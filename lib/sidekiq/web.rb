# frozen_string_literal: true
require 'erb'
require 'yaml'

require 'sidekiq'
require 'sidekiq/api'
require 'sidekiq/paginator'

require 'sidekiq/web/router'
require 'sidekiq/web/application'

require 'rack/protection'

require 'rack/builder'
require 'rack/static'
require 'rack/session/cookie'

module Sidekiq
  class Web
    REQUEST_METHOD = 'REQUEST_METHOD'.freeze
    PATH_INFO = 'PATH_INFO'.freeze

    ROOT = File.expand_path(File.dirname(__FILE__) + "/../../web")
    VIEWS = "#{ROOT}/views"
    LOCALES = ["#{ROOT}/locales"]
    LAYOUT = "#{VIEWS}/layout.erb"
    ASSETS = "#{ROOT}/assets"

    DEFAULT_TABS = {
      "Dashboard" => '',
      "Busy"      => 'busy',
      "Queues"    => 'queues',
      "Retries"   => 'retries',
      "Scheduled" => 'scheduled',
      "Dead"      => 'morgue',
    }

    class << self
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

      def session_secret=(secret)
        @secret = secret
      end

      attr_accessor :app_url, :session_secret
      attr_writer :locales
    end

    def initialize
      secret = Web.session_secret

      if secret.nil?
        require 'securerandom'
        secret = SecureRandom.hex(64)
      end

      @app = ::Rack::Builder.new do
        %w(stylesheets javascripts images).each do |asset_dir|
          map "/#{asset_dir}" do
            run ::Rack::File.new("#{ASSETS}/#{asset_dir}")
          end
        end

        use ::Rack::Session::Cookie, secret: secret
        use ::Rack::Protection, use: :authenticity_token unless ENV['RACK_ENV'] == 'test'

        run WebApplication.new
      end
    end

    def call(env)
      @app.call(env)
    end

    def self.call(env)
      @app ||= new
      @app.call(env)
    end

    def self.register(extension)
      extension.registered(WebApplication)
    end

    ERB.new(File.read LAYOUT).def_method(WebAction, '_render')
  end
end

if defined?(::ActionDispatch::Request::Session) &&
    !::ActionDispatch::Request::Session.respond_to?(:each)
  # mperham/sidekiq#2460
  # Rack apps can't reuse the Rails session store without
  # this monkeypatch
  class ActionDispatch::Request::Session
    def each(&block)
      hash = self.to_hash
      hash.each(&block)
    end
  end
end
