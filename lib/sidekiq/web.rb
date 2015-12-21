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

    enable :sessions
    use ::Rack::Protection, :use => :authenticity_token unless ENV['RACK_ENV'] == 'test'

    set :root, File.expand_path(File.dirname(__FILE__) + "/../../web")
    set :public_folder, proc { "#{root}/assets" }
    set :views, proc { "#{root}/views" }
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

      attr_accessor :app_url
    end

    get "/busy" do
      erb :busy
    end

    post "/busy" do
      if params['identity']
        p = Sidekiq::Process.new('identity' => params['identity'])
        p.quiet! if params[:quiet]
        p.stop! if params[:stop]
      else
        processes.each do |pro|
          pro.quiet! if params[:quiet]
          pro.stop! if params[:stop]
        end
      end
      redirect "#{root_path}busy"
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
      @messages = @messages.map { |msg| Sidekiq::Job.new(msg, @name) }
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
      (@current_page, @total_size, @dead) = page("dead", params[:page], @count, reverse: true)
      @dead = @dead.map { |msg, score| Sidekiq::SortedEntry.new(nil, score, msg) }
      erb :morgue
    end

    get "/morgue/:key" do
      halt 404 unless params['key']
      @dead = Sidekiq::DeadSet.new.fetch(*parse_params(params['key'])).first
      redirect "#{root_path}morgue" if @dead.nil?
      erb :dead
    end

    post '/morgue' do
      redirect request.path unless params['key']

      params['key'].each do |key|
        job = Sidekiq::DeadSet.new.fetch(*parse_params(key)).first
        retry_or_delete_or_kill job, params if job
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
      retry_or_delete_or_kill job, params if job
      redirect_with_query("#{root_path}morgue")
    end


    get '/retries' do
      @count = (params[:count] || 25).to_i
      (@current_page, @total_size, @retries) = page("retry", params[:page], @count)
      @retries = @retries.map { |msg, score| Sidekiq::SortedEntry.new(nil, score, msg) }
      erb :retries
    end

    get "/retries/:key" do
      @retry = Sidekiq::RetrySet.new.fetch(*parse_params(params['key'])).first
      redirect "#{root_path}retries" if @retry.nil?
      erb :retry
    end

    post '/retries' do
      redirect request.path unless params['key']

      params['key'].each do |key|
        job = Sidekiq::RetrySet.new.fetch(*parse_params(key)).first
        retry_or_delete_or_kill job, params if job
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
      job = Sidekiq::RetrySet.new.fetch(*parse_params(params['key'])).first
      retry_or_delete_or_kill job, params if job
      redirect_with_query("#{root_path}retries")
    end

    get '/scheduled' do
      @count = (params[:count] || 25).to_i
      (@current_page, @total_size, @scheduled) = page("schedule", params[:page], @count)
      @scheduled = @scheduled.map { |msg, score| Sidekiq::SortedEntry.new(nil, score, msg) }
      erb :scheduled
    end

    get "/scheduled/:key" do
      @job = Sidekiq::ScheduledSet.new.fetch(*parse_params(params['key'])).first
      redirect "#{root_path}scheduled" if @job.nil?
      erb :scheduled_job_info
    end

    post '/scheduled' do
      redirect request.path unless params['key']

      params['key'].each do |key|
        job = Sidekiq::ScheduledSet.new.fetch(*parse_params(key)).first
        delete_or_add_queue job, params if job
      end
      redirect_with_query("#{root_path}scheduled")
    end

    post "/scheduled/:key" do
      halt 404 unless params['key']
      job = Sidekiq::ScheduledSet.new.fetch(*parse_params(params['key'])).first
      delete_or_add_queue job, params if job
      redirect_with_query("#{root_path}scheduled")
    end

    get '/' do
      @redis_info = redis_info.select{ |k, v| REDIS_KEYS.include? k }
      stats_history = Sidekiq::Stats::History.new((params[:days] || 30).to_i)
      @processed_history = stats_history.processed
      @failed_history = stats_history.failed
      erb :dashboard
    end

    REDIS_KEYS = %w(redis_version uptime_in_days connected_clients used_memory_human used_memory_peak_human)

    get '/dashboard/stats' do
      redirect "#{root_path}stats"
    end

    get '/stats' do
      sidekiq_stats = Sidekiq::Stats.new
      redis_stats   = redis_info.select { |k, v| REDIS_KEYS.include? k }

      content_type :json
      Sidekiq.dump_json(
        sidekiq: {
          processed:       sidekiq_stats.processed,
          failed:          sidekiq_stats.failed,
          busy:            sidekiq_stats.workers_size,
          processes:       sidekiq_stats.processes_size,
          enqueued:        sidekiq_stats.enqueued,
          scheduled:       sidekiq_stats.scheduled_size,
          retries:         sidekiq_stats.retry_size,
          dead:            sidekiq_stats.dead_size,
          default_latency: sidekiq_stats.default_queue_latency
        },
        redis: redis_stats
      )
    end

    get '/stats/queues' do
      queue_stats = Sidekiq::Stats::Queues.new

      content_type :json
      Sidekiq.dump_json(
        queue_stats.lengths
      )
    end

    private

    def retry_or_delete_or_kill job, params
      if params['retry']
        job.retry
      elsif params['delete']
        job.delete
      elsif params['kill']
        job.kill
      end
    end

    def delete_or_add_queue job, params
      if params['delete']
        job.delete
      elsif params['add_to_queue']
        job.add_to_queue
      end
    end
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
