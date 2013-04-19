require 'sinatra/base'
require 'slim'
require 'sidekiq/paginator'

module Sidekiq
  class Web < Sinatra::Base
    include Sidekiq::Paginator

    dir = File.expand_path(File.dirname(__FILE__) + "/../../web")

    set :public_folder, "#{dir}/assets"
    set :views,  "#{dir}/views"
    set :root, "#{dir}/public"
    set :locales, "#{dir}/locales"
    set :slim, :pretty => true

    helpers do
      def strings
        @strings ||= begin
          Dir["#{settings.locales}/*.yml"].inject({}) do |memo, file|
            memo.merge(YAML.load(File.read(file)))
          end
        end
      end

      def get_locale
        (request.env["HTTP_ACCEPT_LANGUAGE"] || 'en')[0,2]
      end

      def t(msg, options={})
        string = strings[get_locale] ? strings[get_locale].fetch(msg) : strings['en'].fetch(msg)
        string % options
      end

      def reset_worker_list
        Sidekiq.redis do |conn|
          workers = conn.smembers('workers')
          workers.each do |name|
            conn.srem('workers', name)
          end
        end
      end

      def workers
        @workers ||= begin
          Sidekiq.redis do |conn|
            conn.smembers('workers').map do |w|
              msg = conn.get("worker:#{w}")
              msg ? [w, Sidekiq.load_json(msg)] : nil
            end.compact.sort { |x| x[1] ? -1 : 1 }
          end
        end
      end

      def stats
        @stats ||= Sidekiq::Stats.new
      end

      def retries_with_score(score)
        Sidekiq.redis do |conn|
          results = conn.zrangebyscore('retry', score, score)
          results.map { |msg| Sidekiq.load_json(msg) }
        end
      end

      def location
        Sidekiq.redis { |conn| conn.client.location }
      end

      def namespace
        @@ns ||= Sidekiq.redis {|conn| conn.respond_to?(:namespace) ? conn.namespace : nil }
      end

      def root_path
        "#{env['SCRIPT_NAME']}/"
      end

      def current_path
        @current_path ||= request.path_info.gsub(/^\//,'')
      end

      def current_status
        return 'idle' if workers.size == 0
        return 'active'
      end

      def relative_time(time)
        %{<time datetime="#{time.getutc.iso8601}">#{time}</time>}
      end

      def job_params(job, score)
        "#{score}-#{job['jid']}"
      end

      def parse_params(params)
        score, jid = params.split("-")
        [score.to_f, jid]
      end

      def display_args(args, count=100)
        args.map { |arg| a = arg.inspect; a.size > count ? "#{a[0..count]}..." : a }.join(", ")
      end

      def tabs
        @tabs ||= {
          "Dashboard" => '',
          "Workers"   => 'workers',
          "Queues"    => 'queues',
          "Retries"   => 'retries',
          "Scheduled" => 'scheduled',
        }
      end

      def custom_tabs
        self.class.tabs
      end

      def number_with_delimiter(number)
        begin
          Float(number)
        rescue ArgumentError, TypeError
          return number
        end

        options = {:delimiter => ',', :separator => '.'}
        parts = number.to_s.to_str.split('.')
        parts[0].gsub!(/(\d)(?=(\d\d\d)+(?!\d))/, "\\1#{options[:delimiter]}")
        parts.join(options[:separator])
      end

      def redis_keys
        ["redis_stats", "uptime_in_days", "connected_clients", "used_memory_human", "used_memory_peak_human"]
      end
    end

    get "/workers" do
      slim :index
    end

    get "/queues" do
      @queues = Sidekiq::Stats.new.queues
      slim :queues
    end

    get "/queues/:name" do
      halt 404 unless params[:name]
      @count = (params[:count] || 25).to_i
      @name = params[:name]
      (@current_page, @total_size, @messages) = page("queue:#{@name}", params[:page], @count)
      @messages = @messages.map {|msg| Sidekiq.load_json(msg) }
      slim :queue
    end

    post "/reset" do
      reset_worker_list
      redirect root_path
    end

    post "/queues/:name" do
      Sidekiq::Queue.new(params[:name]).clear
      redirect "#{root_path}queues"
    end

    post "/queues/:name/delete" do
      Sidekiq::Job.new(params[:key_val], params[:name]).delete
      redirect "#{root_path}queues/#{params[:name]}"
    end

    get '/retries' do
      @count = (params[:count] || 25).to_i
      (@current_page, @total_size, @retries) = page("retry", params[:page], @count)
      @retries = @retries.map {|msg, score| [Sidekiq.load_json(msg), score] }
      slim :retries
    end

    get "/retries/:key" do
      halt 404 unless params['key']
      @retry = Sidekiq::RetrySet.new.fetch(*parse_params(params['key'])).first
      redirect "#{root_path}retries" if @retry.nil?
      slim :retry
    end

    post '/retries' do
      halt 404 unless params['key']

      params['key'].each do |key|
        job = Sidekiq::RetrySet.new.fetch(*parse_params(key)).first
        if params['retry']
          job.retry
        elsif params['delete']
          job.delete
        end
      end
      redirect "#{root_path}retries"
    end

    post "/retries/all/delete" do
      Sidekiq::RetrySet.new.clear
      redirect "#{root_path}retries"
    end

    post "/retries/all/retry" do
      Sidekiq::RetrySet.new.retry_all
      redirect "#{root_path}retries"
    end

    post "/retries/:key" do
      halt 404 unless params['key']
      job = Sidekiq::RetrySet.new.fetch(*parse_params(params['key'])).first
      if params['retry']
        job.retry
      elsif params['delete']
        job.delete
      end
      redirect "#{root_path}retries"
    end

    get '/scheduled' do
      @count = (params[:count] || 25).to_i
      (@current_page, @total_size, @scheduled) = page("schedule", params[:page], @count)
      @scheduled = @scheduled.map {|msg, score| [Sidekiq.load_json(msg), score] }
      slim :scheduled
    end

    post '/scheduled' do
      halt 404 unless params['key']
      halt 404 unless params['delete']
      params['key'].each do |key|
        Sidekiq::ScheduledSet.new.fetch(*parse_params(key)).first.delete
      end
      redirect "#{root_path}scheduled"
    end

    get '/' do
      @redis_info = Sidekiq.redis { |conn| conn.info }.select{ |k, v| redis_keys.include? k }
      stats_history = Sidekiq::Stats::History.new((params[:days] || 30).to_i)
      @processed_history = stats_history.processed
      @failed_history = stats_history.failed
      slim :dashboard
    end

    get '/dashboard/stats' do
      sidekiq_stats = Sidekiq::Stats.new
      redis_stats   = Sidekiq.redis { |conn| conn.info }.select{ |k, v| redis_keys.include? k }

      content_type :json
      Sidekiq.dump_json({
        sidekiq: {
          processed:  sidekiq_stats.processed,
          failed:     sidekiq_stats.failed,
          busy:       workers.size,
          enqueued:   sidekiq_stats.enqueued,
          scheduled:  sidekiq_stats.scheduled_size,
          retries:    sidekiq_stats.retry_size,
        },
        redis: redis_stats
      })
    end

    def self.tabs
      @custom_tabs ||= {}
    end

  end

end

