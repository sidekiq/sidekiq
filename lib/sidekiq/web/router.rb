# frozen_string_literal: true
require 'sidekiq/web/helpers'

module Sidekiq
  module WebRouter
    GET = 'GET'.freeze
    POST = 'POST'.freeze
    HEAD = 'HEAD'.freeze

    ROUTE_PARAMS = 'rack.route_params'.freeze
    REQUEST_METHOD = 'REQUEST_METHOD'.freeze
    PATH_INFO = 'PATH_INFO'.freeze

    def get(path, &block)
      route(GET, path, &block)
    end

    def post(path, &block)
      route(POST, path, &block)
    end

    def route(method, path, &block)
      @routes ||= []
      @routes << WebRoute.new(method, path, block)
    end

    def match(env)
      request_method = env[REQUEST_METHOD]
      request_method = GET if request_method == HEAD
      @routes.each do |route|
        if params = route.match(request_method, env[PATH_INFO])
          env[ROUTE_PARAMS] = params
          return WebAction.new(env, route.app)
        end
      end

      nil
    end
  end

  class WebAction
    include WebHelpers
    include Sidekiq::Paginator

    RACK_SESSION = 'rack.session'.freeze

    CONTENT_TYPE = "Content-Type".freeze
    LOCATION = "Location".freeze

    TEXT_HTML = "text/html".freeze
    APPLICATION_JSON = "application/json".freeze

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

    def render(file)
      output = _render { ERB.new(File.read "#{Web::VIEWS}/#{file}.erb").result(binding) }

      [200, { CONTENT_TYPE => TEXT_HTML }, [output]]
    end

    def redirect(location)
      [302, { LOCATION => "#{request.base_url}#{root_path}#{location}" }, []]
    end

    def json(payload)
      [200, { CONTENT_TYPE => APPLICATION_JSON }, [Sidekiq.dump_json(payload)]]
    end

    def partial(file, locals = {})
      ERB.new(File.read "#{Web::VIEWS}/_#{file}.erb").result(binding)
    end

    def initialize(env, app)
      @env = env
      @app = app
    end

    def retry_or_delete_or_kill(job, params)
      if params['retry']
        job.retry
      elsif params['delete']
        job.delete
      elsif params['kill']
        job.kill
      end
    end

    def delete_or_add_queue(job, params)
      if params['delete']
        job.delete
      elsif params['add_to_queue']
        job.add_to_queue
      end
    end
  end

  class WebRoute
    attr_accessor :request_method, :pattern, :app, :constraints, :name

    NAMED_SEGMENTS_PATTERN = /\/([^\/]*):([^:$\/]+)/.freeze

    def initialize(request_method, pattern, app)
      @request_method = request_method
      @pattern = pattern
      @app = app
    end

    def regexp
      @regexp ||= compile
    end

    def compile
      p = if pattern.match(NAMED_SEGMENTS_PATTERN)
        pattern.gsub(NAMED_SEGMENTS_PATTERN, '/\1(?<\2>[^$/]+)')
      else
        pattern
      end

      Regexp.new("\\A#{p}\\Z")
    end

    def match(request_method, path)
      return nil unless request_method == self.request_method

      if path_match = path.match(regexp)
        params = Hash[path_match.names.map(&:to_sym).zip(path_match.captures)]

        params if meets_constraints(params)
      end
    end

    def meets_constraints(params)
      if constraints
        constraints.each do |param, constraint|
          unless params[param].to_s.match(constraint)
            return false
          end
        end
      end

      true
    end

    def eql?(o)
      o.is_a?(self.class) &&
        o.request_method == request_method &&
        o.pattern == pattern &&
        o.app == app &&
        o.constraints == constraints
    end
    alias == eql?

    def hash
      request_method.hash ^ pattern.hash ^ app.hash ^ constraints.hash
    end
  end
end
