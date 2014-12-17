require 'uri'

module Sidekiq
  # This is not a public API
  module WebHelpers
    def strings
      @@strings ||= begin
        # Allow sidekiq-web extensions to add locale paths
        # so extensions can be localized
        settings.locales.each_with_object({}) do |path,global|
          Dir["#{path}/*.yml"].each_with_object(global) do |file,hash|
            strs = YAML.load(File.open(file))
            hash.deep_merge!(strs)
          end
        end
      end
    end

    # This is a hook for a Sidekiq Pro feature.  Please don't touch.
    def filtering(*)
    end

    def locale
      lang = (request.env["HTTP_ACCEPT_LANGUAGE"] || 'en').split(',')[0].downcase
      strings[lang] ? lang : 'en'
    end

    def get_locale
      strings[locale]
    end

    def t(msg, options={})
      string = get_locale[msg] || msg
      if options.empty?
        string
      else
        string % options
      end
    end

    def workers_size
      @workers_size ||= workers.size
    end

    def workers
      @workers ||= Sidekiq::Workers.new
    end

    def stats
      @stats ||= Sidekiq::Stats.new
    end

    def retries_with_score(score)
      Sidekiq.redis do |conn|
        conn.zrangebyscore('retry', score, score)
      end.map { |msg| Sidekiq.load_json(msg) }
    end

    def location
      Sidekiq.redis { |conn| conn.client.location }
    end

    def redis_connection
      Sidekiq.redis { |conn| conn.client.id }
    end

    def namespace
      @@ns ||= Sidekiq.redis { |conn| conn.respond_to?(:namespace) ? conn.namespace : nil }
    end

    def redis_info
      Sidekiq.redis do |conn|
        # admin commands can't go through redis-namespace starting
        # in redis-namespace 2.0
        if conn.respond_to?(:namespace)
          conn.redis.info
        else
          conn.info
        end
      end
    end

    def root_path
      "#{env['SCRIPT_NAME']}/"
    end

    def current_path
      @current_path ||= request.path_info.gsub(/^\//,'')
    end

    def current_status
      workers_size == 0 ? 'idle' : 'active'
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

    SAFE_QPARAMS = %w(page poll)

    # Merge options with current params, filter safe params, and stringify to query string
    def qparams(options)
      options = options.stringify_keys
      params.merge(options).map do |key, value|
        SAFE_QPARAMS.include?(key) ? "#{key}=#{value}" : next
      end.join("&")
    end

    def truncate(text, truncate_after_chars = 2000)
      truncate_after_chars && text.size > truncate_after_chars ? "#{text[0..truncate_after_chars]}..." : text
    end

    def display_args(args, truncate_after_chars = 2000)
      args.map do |arg|
        a = arg.inspect
        h(truncate(a))
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

    def number_with_delimiter(number)
      begin
        Float(number)
      rescue ArgumentError, TypeError
        return number
      end

      options = {delimiter: ',', separator: '.'}
      parts = number.to_s.to_str.split('.')
      parts[0].gsub!(/(\d)(?=(\d\d\d)+(?!\d))/, "\\1#{options[:delimiter]}")
      parts.join(options[:separator])
    end

    def h(text)
      ::Rack::Utils.escape_html(text)
    rescue ArgumentError => e
      raise unless e.message.eql?('invalid byte sequence in UTF-8')
      text.encode!('UTF-16', 'UTF-8', invalid: :replace, replace: '').encode!('UTF-8', 'UTF-16')
      retry
    end

    # Any paginated list that performs an action needs to redirect
    # back to the proper page after performing that action.
    def redirect_with_query(url)
      r = request.referer
      if r && r =~ /\?/
        ref = URI(r)
        redirect("#{url}?#{ref.query}")
      else
        redirect url
      end
    end

    def environment_title_prefix
      environment = Sidekiq.options[:environment] || ENV['RAILS_ENV'] || ENV['RACK_ENV'] || 'development'

      "[#{environment.upcase}] " unless environment == "production"
    end
  end
end
