# frozen_string_literal: true

require "erb"

module Sidekiq
  class Web
    ##
    # These instance methods are available to all executing ERB
    # templates.
    class Action
      attr_accessor :env, :block

      def initialize(env, block)
        @_erb = false
        @env = env
        @block = block
      end

      def config
        env[:web_config]
      end

      def request
        @request ||= ::Rack::Request.new(env)
      end

      def halt(res)
        throw :halt, [res, {"content-type" => "text/plain"}, [res.to_s]]
      end

      # external redirect
      def redirect_to(url)
        throw :halt, [302, {"Location" => url}, []]
      end

      # internal redirect
      def redirect(location)
        throw :halt, [302, {"Location" => "#{request.base_url}#{location}"}, []]
      end

      def reload_page
        current_location = request.referer.gsub(request.base_url, "")
        redirect current_location
      end

      # stuff after ? or form input
      def params
        # uses string keys, no symbols!
        request.params
      end

      # variables embedded in path, `/metrics/:name`
      def route_params
        # symbol'd keys
        env["rack.route_params"]
      end

      def session
        env["rack.session"]
      end

      def erb(content, options = {})
        if content.is_a? Symbol
          unless respond_to?(:"_erb_#{content}")
            views = options[:views] || Web.views
            filename = "#{views}/#{content}.erb"
            src = ERB.new(File.read(filename)).src

            # Need to use lineno less by 1 because erb generates a
            # comment before the source code.
            Action.class_eval <<-RUBY, filename, -1 # standard:disable Style/EvalWithLocation
              def _erb_#{content}
                #{src}
              end
            RUBY
          end
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
        [200,
          {"content-type" => "application/json", "cache-control" => "private, no-store"},
          [Sidekiq.dump_json(payload)]]
      end

      private

      def _erb(file, locals)
        locals&.each { |k, v| define_singleton_method(k) { v } unless singleton_methods.include? k }

        if file.is_a?(String)
          ERB.new(file).result(binding)
        else
          send(:"_erb_#{file}")
        end
      end

      class_eval <<-RUBY, ::Sidekiq::Web::LAYOUT, -1 # standard:disable Style/EvalWithLocation
        def _render
          #{ERB.new(File.read(::Sidekiq::Web::LAYOUT)).src}
        end
      RUBY
    end
  end
end
