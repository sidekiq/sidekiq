# frozen_string_literal: true

module Sidekiq
  class WebAction
    RACK_SESSION = 'rack.session'.freeze

    LOCATION = "Location".freeze

    CONTENT_TYPE = "Content-Type".freeze
    TEXT_HTML = { CONTENT_TYPE => "text/html".freeze }
    APPLICATION_JSON = { CONTENT_TYPE => "application/json".freeze }

    attr_accessor :env, :block, :type

    def settings
      Web.settings
    end

    def request
      @request ||= ::Rack::Request.new(env)
    end

    def halt(res)
      throw :halt, res
    end

    def redirect(location)
      throw :halt, [302, { LOCATION => "#{request.base_url}#{location}" }, []]
    end

    def params
      indifferent_hash = Hash.new {|hash,key| hash[key.to_s] if Symbol === key }

      indifferent_hash.merge! request.params
      route_params.each {|k,v| indifferent_hash[k.to_s] = v }

      indifferent_hash
    end

    def route_params
      env[WebRouter::ROUTE_PARAMS]
    end

    def session
      env[RACK_SESSION]
    end

    def content_type(type)
      @type = type
    end

    def erb(content, options = {})
      if content.kind_of? Symbol
        content = File.read("#{Web.settings.views}/#{content}.erb")
      end

      if @_erb
        _erb(content, options[:locals])
      else
        @_erb = true
        content = _erb(content, options[:locals])

        _render { content }
      end
    end

    def render(engine, content, options = {})
      raise "Only erb templates are supported" if engine != :erb

      erb(content, options)
    end

    def json(payload)
      [200, APPLICATION_JSON, [Sidekiq.dump_json(payload)]]
    end

    def initialize(env, block)
      @env = env
      @block = block
    end

    private

    def _erb(file, locals)
      locals.each {|k, v| define_singleton_method(k){ v } } if locals

      ERB.new(file).result(binding)
    end
  end
end
