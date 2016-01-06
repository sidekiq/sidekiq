require 'uri'

module Sidekiq
  # This is not a public API
  module WebHelpers
    def strings(lang)
      @@strings ||= {}
      @@strings[lang] ||= begin
        # Allow sidekiq-web extensions to add locale paths
        # so extensions can be localized
        settings.locales.each_with_object({}) do |path, global|
          find_locale_files(lang).each do |file|
            strs = YAML.load(File.open(file))
            global.deep_merge!(strs[lang])
          end
        end
      end
    end

    def clear_caches
      @@strings = nil
      @@locale_files = nil
    end

    def locale_files
      @@locale_files ||= settings.locales.flat_map do |path|
        Dir["#{path}/*.yml"]
      end
    end

    def find_locale_files(lang)
      locale_files.select { |file| file =~ /\/#{lang}\.yml$/ }
    end

    # This is a hook for a Sidekiq Pro feature.  Please don't touch.
    def filtering(*)
    end

    # This view helper provide ability display you html code in
    # to head of page. Example:
    #
    #   <% add_to_head do %>
    #     <link rel="stylesheet" .../>
    #     <meta .../>
    #   <% end %>
    #
    def add_to_head(&block)
      @head_html ||= []
      @head_html << block if block_given?
    end

    def display_custom_head
      return unless defined?(@head_html)
      @head_html.map { |block| capture(&block) }.join
    end

    # Simple capture method for erb templates. The origin was
    # capture method from sinatra-contrib library.
    def capture(&block)
      block.call
      eval('', block.binding)
    end

    # Given a browser request Accept-Language header like
    # "fr-FR,fr;q=0.8,en-US;q=0.6,en;q=0.4,ru;q=0.2", this function
    # will return "fr" since that's the first code with a matching
    # locale in web/locales
    def locale
      @locale ||= begin
        locale = 'en'.freeze
        languages = request.env['HTTP_ACCEPT_LANGUAGE'.freeze] || 'en'.freeze
        languages.downcase.split(','.freeze).each do |lang|
          next if lang == '*'.freeze
          lang = lang.split(';'.freeze)[0]
          break locale = lang if find_locale_files(lang).any?
        end
        locale
      end
    end

    def get_locale
      strings(locale)
    end

    def t(msg, options={})
      string = get_locale[msg] || msg
      if options.empty?
        string
      else
        string % options
      end
    end

    def workers
      @workers ||= Sidekiq::Workers.new
    end

    def processes
      @processes ||= Sidekiq::ProcessSet.new
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
      workers.size == 0 ? 'idle' : 'active'
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
      end.compact.join("&")
    end

    def truncate(text, truncate_after_chars = 2000)
      truncate_after_chars && text.size > truncate_after_chars ? "#{text[0..truncate_after_chars]}..." : text
    end

    def display_args(args, truncate_after_chars = 2000)
      args.map do |arg|
        h(truncate(to_display(arg)))
      end.join(", ")
    end

    def csrf_tag
      "<input type='hidden' name='authenticity_token' value='#{session[:csrf]}'/>"
    end

    def to_display(arg)
      begin
        arg.inspect
      rescue
        begin
          arg.to_s
        rescue => ex
          "Cannot display argument: [#{ex.class.name}] #{ex.message}"
        end
      end
    end

    RETRY_JOB_KEYS = Set.new(%w(
      queue class args retry_count retried_at failed_at
      jid error_message error_class backtrace
      error_backtrace enqueued_at retry wrapped
      created_at
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

    def product_version
      "Sidekiq v#{Sidekiq::VERSION}"
    end

    def redis_connection_and_namespace
      @redis_connection_and_namespace ||= begin
        namespace_suffix = namespace == nil ? '' : "##{namespace}"
        "#{redis_connection}#{namespace_suffix}"
      end
    end
  end
end
