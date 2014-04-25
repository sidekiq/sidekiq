require 'erb'
require 'yaml'
require 'sinatra/base'

require 'sidekiq'
require 'sidekiq/api'
require 'sidekiq/paginator'
require 'sidekiq/web_helpers'

module Sidekiq
  class Web < Sinatra::Base
    include Sidekiq::Paginator

    set :root, File.expand_path(File.dirname(__FILE__) + "/../../web")
    set :public_folder, Proc.new { "#{root}/assets" }
    set :views, Proc.new { "#{root}/views" }
    set :locales, ["#{root}/locales"]

    helpers WebHelpers

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
    end

    get "/busy" do
      erb :busy
    end

    get "/queues" do
      @queues = Sidekiq::Queue.all
      erb :queues
    end

    get "/queues/:name" do
      halt 404 unless params[:name]
      @count = (params[:count] || 25).to_i
      @name = params[:name]
      @queue = Sidekiq::Queue.new(@name)
      (@current_page, @total_size, @messages) = page("queue:#{@name}", params[:page], @count)
      @messages = @messages.map {|msg| Sidekiq.load_json(msg) }
      erb :queue
    end

    post "/queues/:name" do
      Sidekiq::Queue.new(params[:name]).clear
      redirect "#{root_path}queues"
    end

    post "/queues/:name/delete" do
      Sidekiq::Job.new(params[:key_val], params[:name]).delete
      redirect_with_query("#{root_path}queues/#{params[:name]}")
    end

    get '/morgue' do
      @count = (params[:count] || 25).to_i
      (@current_page, @total_size, @dead) = page("dead", params[:page], @count)
      @dead = @dead.map {|msg, score| Sidekiq::SortedEntry.new(nil, score, msg) }
      erb :morgue
    end

    get "/morgue/:key" do
      halt 404 unless params['key']
      @dead = Sidekiq::DeadSet.new.fetch(*parse_params(params['key'])).first
      redirect "#{root_path}morgue" if @dead.nil?
      erb :dead
    end

    post '/morgue' do
      halt 404 unless params['key']

      params['key'].each do |key|
        job = Sidekiq::DeadSet.new.fetch(*parse_params(key)).first
        next unless job
        if params['retry']
          job.retry
        elsif params['delete']
          job.delete
        end
      end
      redirect_with_query("#{root_path}morgue")
    end

    post "/morgue/all/delete" do
      Sidekiq::DeadSet.new.clear
      redirect "#{root_path}morgue"
    end

    post "/morgue/all/retry" do
      Sidekiq::DeadSet.new.retry_all
      redirect "#{root_path}morgue"
    end

    post "/morgue/:key" do
      halt 404 unless params['key']
      job = Sidekiq::DeadSet.new.fetch(*parse_params(params['key'])).first
      if job
        if params['retry']
          job.retry
        elsif params['delete']
          job.delete
        end
      end
      redirect_with_query("#{root_path}morgue")
    end


    get '/retries' do
      @count = (params[:count] || 25).to_i
      (@current_page, @total_size, @retries) = page("retry", params[:page], @count)
      @retries = @retries.map {|msg, score| Sidekiq::SortedEntry.new(nil, score, msg) }
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
      redirect_with_query("#{root_path}retries")
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
      redirect_with_query("#{root_path}retries")
    end

    get '/scheduled' do
      @count = (params[:count] || 25).to_i
      (@current_page, @total_size, @scheduled) = page("schedule", params[:page], @count)
      @scheduled = @scheduled.map {|msg, score| Sidekiq::SortedEntry.new(nil, score, msg) }
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
      redirect_with_query("#{root_path}scheduled")
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
      redirect_with_query("#{root_path}scheduled")
    end

    get '/' do
      @redis_info = Sidekiq.redis { |conn| conn.info }.select{ |k, v| REDIS_KEYS.include? k }
      stats_history = Sidekiq::Stats::History.new((params[:days] || 30).to_i)
      @processed_history = stats_history.processed
      @failed_history = stats_history.failed
      erb :dashboard
    end

    REDIS_KEYS = %w(redis_stats uptime_in_days connected_clients used_memory_human used_memory_peak_human)

    get '/dashboard/stats' do
      sidekiq_stats = Sidekiq::Stats.new
      queue         = Sidekiq::Queue.new
      redis_stats   = Sidekiq.redis { |conn| conn.info }.select{ |k, v| REDIS_KEYS.include? k }

      content_type :json
      Sidekiq.dump_json({
        sidekiq: {
          processed:  sidekiq_stats.processed,
          failed:     sidekiq_stats.failed,
          busy:       workers_size,
          enqueued:   sidekiq_stats.enqueued,
          scheduled:  sidekiq_stats.scheduled_size,
          retries:    sidekiq_stats.retry_size,
          default_latency: queue.latency,
        },
        redis: redis_stats
      })
    end

  end
end
