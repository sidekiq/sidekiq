# frozen_string_literal: true

require "connection_pool"
require "uri"

module Sidekiq
  module RedisConnection
    class << self
      attr_reader :adapter

      def adapter=(adapter)
        raise "no" if adapter == self
        result = case adapter
        when Class
          adapter
        else
          require "sidekiq/#{adapter}_adapter"
          nil
        end
        @adapter = result if result
      end

      def create(options = {})
        symbolized_options = options.transform_keys(&:to_sym)

        if !symbolized_options[:url] && (u = determine_redis_provider)
          symbolized_options[:url] = u
        end

        size = if symbolized_options[:size]
          symbolized_options[:size]
        elsif Sidekiq.server?
          # Give ourselves plenty of connections.  pool is lazy
          # so we won't create them until we need them.
          Sidekiq[:concurrency] + 5
        elsif ENV["RAILS_MAX_THREADS"]
          Integer(ENV["RAILS_MAX_THREADS"])
        else
          5
        end

        verify_sizing(size, Sidekiq[:concurrency]) if Sidekiq.server?

        pool_timeout = symbolized_options[:pool_timeout] || 1
        log_info(symbolized_options)

        redis_config = adapter.new(symbolized_options)
        ConnectionPool.new(timeout: pool_timeout, size: size) do
          redis_config.new_client
        end
      end

      private

      # Sidekiq needs many concurrent Redis connections.
      #
      # We need a connection for each Processor.
      # We need a connection for Pro's real-time change listener
      # We need a connection to various features to call Redis every few seconds:
      #   - the process heartbeat.
      #   - enterprise's leader election
      #   - enterprise's cron support
      def verify_sizing(size, concurrency)
        raise ArgumentError, "Your Redis connection pool is too small for Sidekiq. Your pool has #{size} connections but must have at least #{concurrency + 2}" if size < (concurrency + 2)
      end

      def log_info(options)
        redacted = "REDACTED"

        # Deep clone so we can muck with these options all we want and exclude
        # params from dump-and-load that may contain objects that Marshal is
        # unable to safely dump.
        keys = options.keys - [:logger, :ssl_params]
        scrubbed_options = Marshal.load(Marshal.dump(options.slice(*keys)))
        if scrubbed_options[:url] && (uri = URI.parse(scrubbed_options[:url])) && uri.password
          uri.password = redacted
          scrubbed_options[:url] = uri.to_s
        end
        if scrubbed_options[:password]
          scrubbed_options[:password] = redacted
        end
        scrubbed_options[:sentinels]&.each do |sentinel|
          sentinel[:password] = redacted if sentinel[:password]
        end
        if Sidekiq.server?
          Sidekiq.logger.info("Booting Sidekiq #{Sidekiq::VERSION} with #{adapter.name} options #{scrubbed_options}")
        else
          Sidekiq.logger.debug("#{Sidekiq::NAME} client with #{adapter.name} options #{scrubbed_options}")
        end
      end

      def determine_redis_provider
        # If you have this in your environment:
        # MY_REDIS_URL=redis://hostname.example.com:1238/4
        # then set:
        # REDIS_PROVIDER=MY_REDIS_URL
        # and Sidekiq will find your custom URL variable with no custom
        # initialization code at all.
        #
        p = ENV["REDIS_PROVIDER"]
        if p && p =~ /:/
          raise <<~EOM
            REDIS_PROVIDER should be set to the name of the variable which contains the Redis URL, not a URL itself.
            Platforms like Heroku will sell addons that publish a *_URL variable.  You need to tell Sidekiq with REDIS_PROVIDER, e.g.:

            REDISTOGO_URL=redis://somehost.example.com:6379/4
            REDIS_PROVIDER=REDISTOGO_URL
          EOM
        end

        ENV[
          p || "REDIS_URL"
        ]
      end
    end
  end
end
