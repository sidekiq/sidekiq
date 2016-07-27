# frozen_string_literal: true
module Sidekiq
  class WebApplication
    extend WebRouter

    REDIS_KEYS = %w(redis_version uptime_in_days connected_clients used_memory_human used_memory_peak_human)

    get "/" do
      @redis_info = redis_info.select{ |k, v| REDIS_KEYS.include? k }
      stats_history = Sidekiq::Stats::History.new((params['days'] || 30).to_i)
      @processed_history = stats_history.processed
      @failed_history = stats_history.failed

      render(:dashboard)
    end

    get "/busy" do
      render(:busy)
    end

    post "/busy" do
      if params['identity']
        p = Sidekiq::Process.new('identity' => params['identity'])
        p.quiet! if params['quiet']
        p.stop! if params['stop']
      else
        processes.each do |pro|
          pro.quiet! if params['quiet']
          pro.stop! if params['stop']
        end
      end

      redirect "busy"
    end

    get "/queues" do
      @queues = Sidekiq::Queue.all

      render(:queues)
    end

    get "/queues/:name" do
      @name = route_params[:name]

      next(NOPE) unless @name

      @count = (params['count'] || 25).to_i
      @queue = Sidekiq::Queue.new(@name)
      (@current_page, @total_size, @messages) = page("queue:#{@name}", params['page'], @count)
      @messages = @messages.map { |msg| Sidekiq::Job.new(msg, @name) }

      render(:queue)
    end

    post "/queues/:name" do
      Sidekiq::Queue.new(route_params[:name]).clear

      redirect "queues"
    end

    post "/queues/:name/delete" do
      name = route_params[:name]
      Sidekiq::Job.new(params['key_val'], name).delete

      redirect_with_query("queues/#{name}")
    end

    get '/morgue' do
      @count = (params['count'] || 25).to_i
      (@current_page, @total_size, @dead) = page("dead", params['page'], @count, reverse: true)
      @dead = @dead.map { |msg, score| Sidekiq::SortedEntry.new(nil, score, msg) }

      render(:morgue)
    end

    get "/morgue/:key" do
      next NOPE unless key = route_params[:key]

      @dead = Sidekiq::DeadSet.new.fetch(*parse_params(key)).first

      if @dead.nil?
        redirect "morgue"
      else
        render(:dead)
      end
    end

    post '/morgue' do
      next redirect(request.path) unless params['key']

      params['key'].each do |key|
        job = Sidekiq::DeadSet.new.fetch(*parse_params(key)).first
        retry_or_delete_or_kill job, params if job
      end

      redirect_with_query("morgue")
    end

    post "/morgue/all/delete" do
      Sidekiq::DeadSet.new.clear

      redirect "morgue"
    end

    post "/morgue/all/retry" do
      Sidekiq::DeadSet.new.retry_all

      redirect "morgue"
    end

    post "/morgue/:key" do
      next NOPE unless key = route_params[:key]

      job = Sidekiq::DeadSet.new.fetch(*parse_params(key)).first
      retry_or_delete_or_kill job, params if job

      redirect_with_query("morgue")
    end

    get '/retries' do
      @count = (params['count'] || 25).to_i
      (@current_page, @total_size, @retries) = page("retry", params['page'], @count)
      @retries = @retries.map { |msg, score| Sidekiq::SortedEntry.new(nil, score, msg) }

      render(:retries)
    end

    get "/retries/:key" do
      @retry = Sidekiq::RetrySet.new.fetch(*parse_params(route_params[:key])).first

      if @retry.nil?
        redirect "retries"
      else
        render(:retry)
      end
    end

    post '/retries' do
      next redirect(request.path) unless params['key']

      params['key'].each do |key|
        job = Sidekiq::RetrySet.new.fetch(*parse_params(key)).first
        retry_or_delete_or_kill job, params if job
      end

      redirect_with_query("retries")
    end

    post "/retries/all/delete" do
      Sidekiq::RetrySet.new.clear

      redirect "retries"
    end

    post "/retries/all/retry" do
      Sidekiq::RetrySet.new.retry_all

      redirect "retries"
    end

    post "/retries/:key" do
      job = Sidekiq::RetrySet.new.fetch(*parse_params(route_params[:key])).first

      retry_or_delete_or_kill job, params if job

      redirect_with_query("retries")
    end

    get '/scheduled' do
      @count = (params['count'] || 25).to_i
      (@current_page, @total_size, @scheduled) = page("schedule", params['page'], @count)
      @scheduled = @scheduled.map { |msg, score| Sidekiq::SortedEntry.new(nil, score, msg) }

      render(:scheduled)
    end

    get "/scheduled/:key" do
      @job = Sidekiq::ScheduledSet.new.fetch(*parse_params(route_params[:key])).first

      if @job.nil?
        redirect "scheduled"
      else
        render(:scheduled_job_info)
      end
    end

    post '/scheduled' do
      next redirect(request.path) unless params['key']

      params['key'].each do |key|
        job = Sidekiq::ScheduledSet.new.fetch(*parse_params(key)).first
        delete_or_add_queue job, params if job
      end

      redirect_with_query("scheduled")
    end

    post "/scheduled/:key" do
      next NOPE unless key = route_params[:key]

      job = Sidekiq::ScheduledSet.new.fetch(*parse_params(key)).first
      delete_or_add_queue job, params if job

      redirect_with_query("scheduled")
    end

    get '/dashboard/stats' do
      redirect "stats"
    end

    get '/stats' do
      sidekiq_stats = Sidekiq::Stats.new
      redis_stats   = redis_info.select { |k, v| REDIS_KEYS.include? k }

      json(
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
      json Sidekiq::Stats::Queues.new.lengths
    end

    NOPE = [404, {}, []]

    def call(env)
      action = self.class.match(env)
      return NOPE unless action

      self.class.run_befores(env)
      resp = action.instance_exec env, &action.app
      self.class.run_afters(env)
      resp
    end

    def self.helpers(mod)
      WebAction.send(:include, mod)
    end

    def self.before(&block)
      befores << block
    end

    def self.after(&block)
      afters << block
    end

    def self.run_befores(env)
      befores.each do |b|
        b.call(env)
      end
    end

    def self.run_afters(env)
      afters.each do |b|
        b.call(env)
      end
    end

    def self.befores
      @befores ||= []
    end

    def self.afters
      @afters ||= []
    end

  end
end
