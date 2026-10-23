# frozen_string_literal: true

require "connection_pool"
require "uri"
require "sidekiq/redis_client_adapter"

module Sidekiq
  module RedisConnection
    LOCATION_KEYS = %i[url host port path sentinels].freeze

    class << self
      def create(options = {})
        symbolized_options = deep_symbolize_keys(options)
        symbolized_options[:url] ||= determine_redis_provider
        verify_location!(symbolized_options) if ENV["SIDEKIQ_REQUIRE_REDIS_CONFIG"]
        symbolized_options[:password] = wrap(symbolized_options[:password]) if symbolized_options.key?(:password)
        symbolized_options[:sentinel_password] = wrap(symbolized_options[:sentinel_password]) if symbolized_options.key?(:sentinel_password)

        logger = symbolized_options.delete(:logger)
        logger&.info { "Sidekiq #{Sidekiq::VERSION} connecting to Redis with options #{scrub(symbolized_options)}" }

        raise "Sidekiq 7+ does not support Redis protocol 2" if symbolized_options[:protocol] == 2

        safe = !!symbolized_options.delete(:cluster_safe)
        raise ":nodes not allowed, Sidekiq is not safe to run on Redis Cluster" if !safe && symbolized_options.key?(:nodes)

        size = symbolized_options.delete(:size) || 5
        pool_timeout = symbolized_options.delete(:pool_timeout) || 1
        symbolized_options.delete(:pool_name)

        # Default timeout in redis-client is 1 second, which can be too aggressive
        # if the Sidekiq process is CPU-bound. With 10-15 threads and a thread quantum of 100ms,
        # it can be easy to get the occasional ReadTimeoutError. You can still provide
        # a smaller timeout explicitly:
        #     config.redis = { url: "...", timeout: 1 }
        symbolized_options[:timeout] ||= 3

        redis_config = Sidekiq::RedisClientAdapter.new(symbolized_options)
        # Only the main Ractor can fork, and connection_pool's fork registry
        # is a non-shareable constant other Ractors can't touch.
        main = Ractor.current == Ractor.main
        ConnectionPool.new(timeout: pool_timeout, size: size, auto_reload_after_fork: main) do
          redis_config.new_client
        end
      end

      private

      # SIDEKIQ_REQUIRE_REDIS_CONFIG=1 refuses to build a pool when no Redis
      # location was given, instead of letting redis-client default to
      # localhost:6379. In a Rails app this catches code that uses Sidekiq.redis
      # before the configure block in config/initializers has run; without it
      # the first pool is memoized against localhost and the configuration that
      # arrives later is ignored. It is an environment variable rather than a
      # config option because an option set in an initializer would have the
      # same ordering problem it is meant to catch.
      def verify_location!(options)
        return if LOCATION_KEYS.any? { |key| present?(options[key]) }

        raise ArgumentError, "SIDEKIQ_REQUIRE_REDIS_CONFIG is set and no Redis location is configured. " \
          "Set `config.redis = { url: ... }` before Sidekiq.redis is used, or set REDIS_URL."
      end

      def present?(value)
        value.is_a?(String) ? !value.empty? : !value.nil?
      end

      # Wrap hard-coded passwords in a Proc to avoid logging the value
      def wrap(pwd)
        if pwd.is_a?(String)
          ->(username) { pwd }
        else
          pwd
        end
      end

      def deep_symbolize_keys(object)
        case object
        when Hash
          object.each_with_object({}) do |(key, value), result|
            result[key.to_sym] = deep_symbolize_keys(value)
          end
        when Array
          object.map { |e| deep_symbolize_keys(e) }
        else
          object
        end
      end

      def scrub(options)
        redacted = "REDACTED"

        # Deep clone so we can muck with these options all we want and exclude
        # params from dump-and-load that may contain objects that Marshal is
        # unable to safely dump.
        keys = options.keys - [:logger, :ssl_params, :password, :sentinel_password]
        scrubbed_options = Marshal.load(Marshal.dump(options.slice(*keys)))
        scrubbed_options[:url] = redact_uri(scrubbed_options[:url], redacted) if scrubbed_options[:url]
        scrubbed_options[:password] = redacted if options.key?(:password)
        scrubbed_options[:sentinel_password] = redacted if options.key?(:sentinel_password)
        scrubbed_options[:sentinels]&.each do |sentinel|
          if sentinel.is_a?(String)
            sentinel.replace(redact_uri(sentinel, redacted))
          elsif sentinel[:password]
            sentinel[:password] = redacted
          end
        end
        scrubbed_options
      end

      # Replace the password in a Redis URL. A URL which can't be parsed may
      # still hold a password, so it is redacted completely rather than letting
      # URI::InvalidURIError (which quotes the URL) escape.
      def redact_uri(url, redacted)
        uri = URI.parse(url)
        return url unless uri.password
        uri.password = redacted
        uri.to_s
      rescue URI::InvalidURIError
        redacted
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

        ENV[p.to_s] || ENV["REDIS_URL"]
      end
    end
  end
end
