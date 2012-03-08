require 'sinatra/base'
require 'slim'
require 'sprockets'

module Sidekiq
  class SprocketsMiddleware
    def initialize(app, options={})
      @app = app
      @root = options[:root]
      path   =  options[:path] || 'assets'
      @matcher = /^\/#{path}\/*/
      @environment = ::Sprockets::Environment.new(@root)
      @environment.append_path 'assets/javascripts'
      @environment.append_path 'assets/javascripts/vendor'
      @environment.append_path 'assets/stylesheets'
      @environment.append_path 'assets/stylesheets/vendor'
      @environment.append_path 'assets/images'
    end

    def call(env)
      # Solve the problem of people requesting /sidekiq when they need to request /sidekiq/ so
      # that relative links in templates resolve correctly.
      return [301, { 'Location' => "#{env['SCRIPT_NAME']}/" }, []] if env['SCRIPT_NAME'] == env['REQUEST_PATH']

      return @app.call(env) unless @matcher =~ env["PATH_INFO"]
      env['PATH_INFO'].sub!(@matcher,'')
      @environment.call(env)
    end
  end

  class Web < Sinatra::Base
    dir = File.expand_path(File.dirname(__FILE__) + "/../../web")
    set :views,  "#{dir}/views"
    set :root, "#{dir}/public"
    set :slim, :pretty => true
    use SprocketsMiddleware, :root => dir

    helpers do
      def workers
        @workers ||= begin
          Sidekiq.redis.with_connection do |conn|
            conn.smembers('workers').map do |w|
              msg = conn.get("worker:#{w}")
              msg = MultiJson.decode(msg) if msg
              [w, msg]
            end.sort { |x| x[1] ? -1 : 1 }
          end
        end
      end

      def processed
        Sidekiq.redis.get('stat:processed') || 0
      end

      def failed
        Sidekiq.redis.get('stat:failed') || 0
      end

      def queues
        Sidekiq.redis.with_connection do |conn|
          conn.smembers('queues').map do |q|
            [q, conn.llen("queue:#{q}") || 0]
          end.sort { |x,y| x[1] <=> y[1] }
        end
      end

      def location
        Sidekiq.redis.client.location
      end

      def root_path
        "#{env['SCRIPT_NAME']}/"
      end

      def status
        return 'down' if workers.size == 0
        return 'idle' if workers.size > 0 && workers.map { |x| x[1] }.compact.size == 0
        return 'active'
      end
    end

    get "/" do
      slim :index
    end

    get "/queues/:name" do
      @name = params[:name]
      @messages = Sidekiq.redis.lrange("queue:#{@name}", 0, 10).map { |str| MultiJson.decode(str) }
      slim :queue
    end
  end

end
