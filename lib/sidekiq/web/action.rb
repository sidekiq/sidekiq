# frozen_string_literal: true

module Sidekiq
  class WebAction
    RACK_SESSION = 'rack.session'.freeze

    LOCATION = "Location".freeze

    TEXT_HTML = { "Content-Type".freeze => "text/html".freeze }
    APPLICATION_JSON = { "Content-Type".freeze => "application/json".freeze }

    attr_accessor :env, :app

    def request
      @request ||= Rack::Request.new(env)
    end

    def params
      request.params
    end

    def route_params
      env[WebRouter::ROUTE_PARAMS]
    end

    def session
      env[RACK_SESSION]
    end

    def erb(content, options = {})
      b = binding

      if locals = options[:locals]
        locals.each {|k, v| b.local_variable_set(k, v) }
      end

      _render { ERB.new(content).result(b) }
    end

    def partial(file, locals = {})
      ERB.new(File.read "#{Web::VIEWS}/_#{file}.erb").result(binding)
    end

    def redirect(location)
      [302, { LOCATION => "#{request.base_url}#{root_path}#{location}" }, []]
    end

    def render(file, locals = {})
      output = erb(File.read "#{Web::VIEWS}/#{file}.erb", locals: locals)

      [200, TEXT_HTML, [output]]
    end

    def json(payload)
      [200, APPLICATION_JSON, [Sidekiq.dump_json(payload)]]
    end

    def initialize(env, app)
      @env = env
      @app = app
    end
  end
end
