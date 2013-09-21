require 'erb'
require 'yaml'
require 'sinatra/base'

require 'sidekiq'
require 'sidekiq/api'
require 'sidekiq/paginator'

module Sidekiq
  class Web < Sinatra::Base
    include Sidekiq::Paginator

    set :root, File.expand_path(File.dirname(__FILE__) + "/../../web")
    set :public_folder, Proc.new { "#{root}/assets" }
    set :views, Proc.new { "#{root}/views" }
    set :locales, Proc.new { "#{root}/locales" }

    helpers do
      def strings
        @strings ||= begin
          Dir["#{settings.locales}/*.yml"].inject({}) do |memo, file|
            memo.merge(YAML.load(File.open(file)))
          end
        end
      end

      def locale
        lang = (request.env["HTTP_ACCEPT_LANGUAGE"] || 'en')[0,2]
        strings[lang] ? lang : 'en'
      end

      def get_locale
        strings[locale]
      end

      def t(msg, options={})
        string = get_locale[msg] || msg
        string % options
      end

      def reset_worker_list
        Sidekiq.redis do |conn|
          workers = conn.smembers('workers')
          conn.srem('workers', workers) if !workers.empty?
        end
      end

      def workers_size
        @workers_size ||= Sidekiq.redis do |conn|
          conn.scard('workers')
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
        return 'idle' if workers_size == 0
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

      def truncate(text, truncate_after_chars = 2000)
        truncate_after_chars && text.size > truncate_after_chars ? "#{text[0..truncate_after_chars]}..." : text
      end

      def display_args(args, truncate_after_chars = 2000)
        args.map do |arg|
          a = arg.inspect
          truncate(a)
        end.join(", ")
      end

      RETRY_JOB_KEYS = Set.new(%w(
        queue class args retry_count retried_at failed_at
        jid error_message error_class backtrace
        error_backtrace enqueued_at retry
      ))

      def retry_extra_items(retry_job)
        @retry_extra_items ||= {}.tap do |extra|
          retry_job.item.each do |key, value|
            extra[key] = value unless RETRY_JOB_KEYS.include?(key)
          end
        end
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

      def h(text)
        ERB::Util.h(text)
      end
    end

    get "/workers" do
      erb :index
    end

    get "/queues" do
      @queues = Sidekiq::Queue.all
      erb :queues
    end

    get "/queues/:name" do
      halt 404 unless params[:name]
      @count = (params[:count] || 25).to_i
      @name = params[:name]
      (@current_page, @total_size, @messages) = page("queue:#{@name}", params[:page], @count)
      @messages = @messages.map {|msg| Sidekiq.load_json(msg) }
      erb :queue
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
      erb :retries
    end

    get "/retries/:key" do
      halt 404 unless params['key']
      @retry = Sidekiq::RetrySet.new.fetch(*parse_params(params['key'])).first
      redirect "#{root_path}retries" if @retry.nil?
      erb :retry
    end

    post '/retries' do
      halt 404 unless params['key']

      params['key'].each do |key|
        job = Sidekiq::RetrySet.new.fetch(*parse_params(key)).first
        next unless job
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
      if job
        if params['retry']
          job.retry
        elsif params['delete']
          job.delete
        end
      end
      redirect "#{root_path}retries"
    end

    get '/scheduled' do
      @count = (params[:count] || 25).to_i
      (@current_page, @total_size, @scheduled) = page("schedule", params[:page], @count)
      @scheduled = @scheduled.map {|msg, score| [Sidekiq.load_json(msg), score] }
      erb :scheduled
    end

    get "/scheduled/:key" do
      halt 404 unless params['key']
      @job = Sidekiq::ScheduledSet.new.fetch(*parse_params(params['key'])).first
      redirect "#{root_path}scheduled" if @job.nil?
      erb :scheduled_job_info
    end

    post '/scheduled' do
      halt 404 unless params['key']

      params['key'].each do |key|
        job = Sidekiq::ScheduledSet.new.fetch(*parse_params(key)).first
        if job
          if params['delete']
            job.delete
          elsif params['add_to_queue']
            job.add_to_queue
          end
        end
      end
      redirect "#{root_path}scheduled"
    end

    post "/scheduled/:key" do
      halt 404 unless params['key']
      job = Sidekiq::ScheduledSet.new.fetch(*parse_params(params['key'])).first
      if job
        if params['add_to_queue']
          job.add_to_queue
        elsif params['delete']
          job.delete
        end
      end
      redirect "#{root_path}scheduled"
    end

    get '/' do
      @redis_info = Sidekiq.redis { |conn| conn.info }.select{ |k, v| redis_keys.include? k }
      stats_history = Sidekiq::Stats::History.new((params[:days] || 30).to_i)
      @processed_history = stats_history.processed
      @failed_history = stats_history.failed
      erb :dashboard
    end

    get '/dashboard/stats' do
      sidekiq_stats = Sidekiq::Stats.new
      redis_stats   = Sidekiq.redis { |conn| conn.info }.select{ |k, v| redis_keys.include? k }

      content_type :json
      Sidekiq.dump_json({
        sidekiq: {
          processed:  sidekiq_stats.processed,
          failed:     sidekiq_stats.failed,
          busy:       workers_size,
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
