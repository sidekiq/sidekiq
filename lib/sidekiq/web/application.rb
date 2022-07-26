# frozen_string_literal: true

module Sidekiq
  class WebApplication
    extend WebRouter

    REDIS_KEYS = %w[redis_version uptime_in_days connected_clients used_memory_human used_memory_peak_human]
    CSP_HEADER = [
      "default-src 'self' https: http:",
      "child-src 'self'",
      "connect-src 'self' https: http: wss: ws:",
      "font-src 'self' https: http:",
      "frame-src 'self'",
      "img-src 'self' https: http: data:",
      "manifest-src 'self'",
      "media-src 'self'",
      "object-src 'none'",
      "script-src 'self' https: http: 'unsafe-inline'",
      "style-src 'self' https: http: 'unsafe-inline'",
      "worker-src 'self'",
      "base-uri 'self'"
    ].join("; ").freeze

    def initialize(klass)
      @klass = klass
    end

    def settings
      @klass.settings
    end

    def self.settings
      Sidekiq::Web.settings
    end

    def self.tabs
      Sidekiq::Web.tabs
    end

    def self.set(key, val)
      # nothing, backwards compatibility
    end

    head "/" do
      # HEAD / is the cheapest heartbeat possible,
      # it hits Redis to ensure connectivity
      Sidekiq.redis { |c| c.llen("queue:default") }
      ""
    end

    get "/" do
      @redis_info = redis_info.select { |k, v| REDIS_KEYS.include? k }
      days = (params["days"] || 30).to_i
      return halt(401) if days < 1 || days > 180

      stats_history = Sidekiq::Stats::History.new(days)
      @processed_history = stats_history.processed
      @failed_history = stats_history.failed

      erb(:dashboard)
    end

    get "/metrics" do
      q = Sidekiq::Metrics::Query.new
      @resultset = q.top_jobs
      erb(:metrics)
    end

    get "/metrics/:name" do
      @name = route_params[:name]
      q = Sidekiq::Metrics::Query.new
      @resultset = q.for_job(@name)
      erb(:metrics_for_job)
    end

    get "/busy" do
      erb(:busy)
    end

    post "/busy" do
      if params["identity"]
        p = Sidekiq::Process.new("identity" => params["identity"])
        p.quiet! if params["quiet"]
        p.stop! if params["stop"]
      else
        processes.each do |pro|
          pro.quiet! if params["quiet"]
          pro.stop! if params["stop"]
        end
      end

      redirect "#{root_path}busy"
    end

    get "/queues" do
      @queues = Sidekiq::Queue.all

      erb(:queues)
    end

    QUEUE_NAME = /\A[a-z_:.\-0-9]+\z/i

    get "/queues/:name" do
      @name = route_params[:name]

      halt(404) if !@name || @name !~ QUEUE_NAME

      @count = (params["count"] || 25).to_i
      @queue = Sidekiq::Queue.new(@name)
      (@current_page, @total_size, @jobs) = page("queue:#{@name}", params["page"], @count, reverse: params["direction"] == "asc")
      @jobs = @jobs.map { |msg| Sidekiq::JobRecord.new(msg, @name) }

      erb(:queue)
    end

    post "/queues/:name" do
      queue = Sidekiq::Queue.new(route_params[:name])

      if Sidekiq.pro? && params["pause"]
        queue.pause!
      elsif Sidekiq.pro? && params["unpause"]
        queue.unpause!
      else
        queue.clear
      end

      redirect "#{root_path}queues"
    end

    post "/queues/:name/delete" do
      name = route_params[:name]
      Sidekiq::JobRecord.new(params["key_val"], name).delete

      redirect_with_query("#{root_path}queues/#{CGI.escape(name)}")
    end

    get "/morgue" do
      @count = (params["count"] || 25).to_i
      (@current_page, @total_size, @dead) = page("dead", params["page"], @count, reverse: true)
      @dead = @dead.map { |msg, score| Sidekiq::SortedEntry.new(nil, score, msg) }

      erb(:morgue)
    end

    get "/morgue/:key" do
      key = route_params[:key]
      halt(404) unless key

      @dead = Sidekiq::DeadSet.new.fetch(*parse_params(key)).first

      if @dead.nil?
        redirect "#{root_path}morgue"
      else
        erb(:dead)
      end
    end

    post "/morgue" do
      redirect(request.path) unless params["key"]

      params["key"].each do |key|
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
      key = route_params[:key]
      halt(404) unless key

      job = Sidekiq::DeadSet.new.fetch(*parse_params(key)).first
      retry_or_delete_or_kill job, params if job

      redirect_with_query("#{root_path}morgue")
    end

    get "/retries" do
      @count = (params["count"] || 25).to_i
      (@current_page, @total_size, @retries) = page("retry", params["page"], @count)
      @retries = @retries.map { |msg, score| Sidekiq::SortedEntry.new(nil, score, msg) }

      erb(:retries)
    end

    get "/retries/:key" do
      @retry = Sidekiq::RetrySet.new.fetch(*parse_params(route_params[:key])).first

      if @retry.nil?
        redirect "#{root_path}retries"
      else
        erb(:retry)
      end
    end

    post "/retries" do
      redirect(request.path) unless params["key"]

      params["key"].each do |key|
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

    post "/retries/all/kill" do
      Sidekiq::RetrySet.new.kill_all

      redirect "#{root_path}retries"
    end

    post "/retries/:key" do
      job = Sidekiq::RetrySet.new.fetch(*parse_params(route_params[:key])).first

      retry_or_delete_or_kill job, params if job

      redirect_with_query("#{root_path}retries")
    end

    get "/scheduled" do
      @count = (params["count"] || 25).to_i
      (@current_page, @total_size, @scheduled) = page("schedule", params["page"], @count)
      @scheduled = @scheduled.map { |msg, score| Sidekiq::SortedEntry.new(nil, score, msg) }

      erb(:scheduled)
    end

    get "/scheduled/:key" do
      @job = Sidekiq::ScheduledSet.new.fetch(*parse_params(route_params[:key])).first

      if @job.nil?
        redirect "#{root_path}scheduled"
      else
        erb(:scheduled_job_info)
      end
    end

    post "/scheduled" do
      redirect(request.path) unless params["key"]

      params["key"].each do |key|
        job = Sidekiq::ScheduledSet.new.fetch(*parse_params(key)).first
        delete_or_add_queue job, params if job
      end

      redirect_with_query("#{root_path}scheduled")
    end

    post "/scheduled/:key" do
      key = route_params[:key]
      halt(404) unless key

      job = Sidekiq::ScheduledSet.new.fetch(*parse_params(key)).first
      delete_or_add_queue job, params if job

      redirect_with_query("#{root_path}scheduled")
    end

    get "/dashboard/stats" do
      redirect "#{root_path}stats"
    end

    get "/stats" do
      sidekiq_stats = Sidekiq::Stats.new
      redis_stats = redis_info.select { |k, v| REDIS_KEYS.include? k }
      json(
        sidekiq: {
          processed: sidekiq_stats.processed,
          failed: sidekiq_stats.failed,
          busy: sidekiq_stats.workers_size,
          processes: sidekiq_stats.processes_size,
          enqueued: sidekiq_stats.enqueued,
          scheduled: sidekiq_stats.scheduled_size,
          retries: sidekiq_stats.retry_size,
          dead: sidekiq_stats.dead_size,
          default_latency: sidekiq_stats.default_queue_latency
        },
        redis: redis_stats,
        server_utc_time: server_utc_time
      )
    end

    get "/stats/queues" do
      json Sidekiq::Stats::Queues.new.lengths
    end

    def call(env)
      action = self.class.match(env)
      return [404, {"Content-Type" => "text/plain", "X-Cascade" => "pass"}, ["Not Found"]] unless action

      app = @klass
      resp = catch(:halt) do
        self.class.run_befores(app, action)
        action.instance_exec env, &action.block
      ensure
        self.class.run_afters(app, action)
      end

      case resp
      when Array
        # redirects go here
        resp
      else
        # rendered content goes here
        headers = {
          "Content-Type" => "text/html",
          "Cache-Control" => "private, no-store",
          "Content-Language" => action.locale,
          "Content-Security-Policy" => CSP_HEADER
        }
        # we'll let Rack calculate Content-Length for us.
        [200, headers, [resp]]
      end
    end

    def self.helpers(mod = nil, &block)
      if block
        WebAction.class_eval(&block)
      else
        WebAction.send(:include, mod)
      end
    end

    def self.before(path = nil, &block)
      befores << [path && Regexp.new("\\A#{path.gsub("*", ".*")}\\z"), block]
    end

    def self.after(path = nil, &block)
      afters << [path && Regexp.new("\\A#{path.gsub("*", ".*")}\\z"), block]
    end

    def self.run_befores(app, action)
      run_hooks(befores, app, action)
    end

    def self.run_afters(app, action)
      run_hooks(afters, app, action)
    end

    def self.run_hooks(hooks, app, action)
      hooks.select { |p, _| !p || p =~ action.env[WebRouter::PATH_INFO] }
        .each { |_, b| action.instance_exec(action.env, app, &b) }
    end

    def self.befores
      @befores ||= []
    end

    def self.afters
      @afters ||= []
    end
  end
end
