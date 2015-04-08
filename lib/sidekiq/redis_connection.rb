require 'connection_pool'
require 'redis'
require 'uri'

module Sidekiq
  class RedisConnection
    class << self

      def create(options={})
        options[:url] ||= determine_redis_provider

        # need a connection for Fetcher and Retry
        size = options[:size] || (Sidekiq.server? ? (Sidekiq.options[:concurrency] + 2) : 5)
        pool_timeout = options[:pool_timeout] || 1

        log_info(options)

        ConnectionPool.new(:timeout => pool_timeout, :size => size) do
          build_client(options)
        end
      end

      private

      REDIS_MIN_VERSION = '2.4'.freeze

      def build_client(options)
        namespace = options[:namespace]

        client = Redis.new client_opts(options)
        check_redis_version(client)
        if namespace
          require 'redis/namespace'
          Redis::Namespace.new(namespace, :redis => client)
        else
          client
        end
      end

      def check_redis_version(client)
        redis_version = Gem::Version.new(client.info['redis_version'])
        required_version = Gem::Version.new(REDIS_MIN_VERSION)
        if required_version > redis_version
          raise "Sidekiq requires redis #{REDIS_MIN_VERSION} or greater, your current version is #{version}"
        end
      end

      def client_opts(options)
        opts = options.dup
        if opts[:namespace]
          opts.delete(:namespace)
        end

        if opts[:network_timeout]
          opts[:timeout] = opts[:network_timeout]
          opts.delete(:network_timeout)
        end

        opts[:driver] = opts[:driver] || 'ruby'

        opts
      end

      def log_info(options)
        # Don't log Redis AUTH password
        redacted = "REDACTED"
        scrubbed_options = options.dup
        if scrubbed_options[:url] && (uri = URI.parse(scrubbed_options[:url])) && uri.password
          uri.password = redacted
          scrubbed_options[:url] = uri.to_s
        end
        if scrubbed_options[:password]
          scrubbed_options[:password] = redacted
        end
        if Sidekiq.server?
          Sidekiq.logger.info("Booting Sidekiq #{Sidekiq::VERSION} with redis options #{scrubbed_options}")
        else
          Sidekiq.logger.debug("#{Sidekiq::NAME} client with redis options #{scrubbed_options}")
        end
      end

      def determine_redis_provider
        ENV[ENV['REDIS_PROVIDER'] || 'REDIS_URL']
      end

    end
  end
end
