# frozen_string_literal: true

require_relative "helper"
require "sidekiq/cli"

describe Sidekiq::RedisClientConnection do
  describe "create" do
    before do
      @previous_adapter = Sidekiq::RedisConnection.adapter
      Sidekiq::RedisConnection.adapter = Sidekiq::RedisClientConnection
      Sidekiq.options = Sidekiq::DEFAULTS.dup
      @old = ENV["REDIS_URL"]
      ENV["REDIS_URL"] = "redis://localhost/15"
    end

    after do
      ENV["REDIS_URL"] = @old
      Sidekiq::RedisConnection.adapter = @previous_adapter
    end

    it "creates a pooled redis connection" do
      pool = Sidekiq::RedisClientConnection.create
      assert_equal Sidekiq::RedisClientConnection::CompatClient, pool.checkout.class
    end

    # Readers for these ivars should be available in the next release of
    # `connection_pool`, until then we need to reach into the internal state to
    # verify the setting.
    describe "size" do
      def client_connection(*args)
        Sidekiq.stub(:server?, nil) do
          Sidekiq::RedisClientConnection.create(*args)
        end
      end

      def server_connection(*args)
        Sidekiq.stub(:server?, "constant") do
          Sidekiq::RedisClientConnection.create(*args)
        end
      end

      it "uses the specified custom pool size" do
        pool = client_connection(size: 42)
        assert_equal 42, pool.instance_eval { @size }
        assert_equal 42, pool.instance_eval { @available.length }

        pool = server_connection(size: 42)
        assert_equal 42, pool.instance_eval { @size }
        assert_equal 42, pool.instance_eval { @available.length }
      end

      it "defaults server pool sizes based on concurrency with padding" do
        _expected_padding = 5
        prev_concurrency = Sidekiq.options[:concurrency]
        Sidekiq.options[:concurrency] = 6
        pool = server_connection

        assert_equal 11, pool.instance_eval { @size }
        assert_equal 11, pool.instance_eval { @available.length }
      ensure
        Sidekiq.options[:concurrency] = prev_concurrency
      end

      it "defaults client pool sizes to 5" do
        pool = client_connection

        assert_equal 5, pool.instance_eval { @size }
        assert_equal 5, pool.instance_eval { @available.length }
      end

      it "changes client pool sizes with ENV" do
        ENV["RAILS_MAX_THREADS"] = "9"
        pool = client_connection

        assert_equal 9, pool.instance_eval { @size }
        assert_equal 9, pool.instance_eval { @available.length }
      ensure
        ENV.delete("RAILS_MAX_THREADS")
      end
    end

    it "disables client setname with nil id" do
      pool = Sidekiq::RedisClientConnection.create(id: nil)
      assert_equal Sidekiq::RedisClientConnection::CompatClient, pool.checkout.class
      assert_nil pool.checkout.id
    end

    describe "namespace" do
      it "does not support it" do
        assert_raises ArgumentError do
          Sidekiq::RedisClientConnection.create(namespace: "xxx")
        end
      end
    end

    describe "network_timeout" do
      it "sets a custom network_timeout if specified" do
        pool = Sidekiq::RedisClientConnection.create(network_timeout: 8)
        redis = pool.checkout

        assert_equal 8, redis.read_timeout
      end

      it "uses the default network_timeout if none specified" do
        pool = Sidekiq::RedisClientConnection.create
        redis = pool.checkout

        assert_equal 1.0, redis.read_timeout
      end
    end

    describe "socket path" do
      it "uses a given :path" do
        pool = Sidekiq::RedisClientConnection.create(path: "/var/run/redis.sock")
        assert_equal "/var/run/redis.sock", pool.checkout.config.path
      end
    end

    describe "db" do
      it "uses a given :db" do
        pool = Sidekiq::RedisClientConnection.create(db: 8)
        assert_includes pool.checkout.call("CLIENT", "INFO"), " db=8 "
      end
    end

    describe "pool_timeout" do
      it "uses a given :timeout over the default of 1" do
        pool = Sidekiq::RedisClientConnection.create(pool_timeout: 5)

        assert_equal 5, pool.instance_eval { @timeout }
      end

      it "uses the default timeout of 1 if no override" do
        pool = Sidekiq::RedisClientConnection.create

        assert_equal 1, pool.instance_eval { @timeout }
      end
    end

    describe "logging redis options" do
      it "redacts credentials" do
        options = {
          role: "master",
          master_name: "mymaster",
          sentinels: [
            {host: "host1", port: 26379, password: "secret"},
            {host: "host2", port: 26379, password: "secret"},
            {host: "host3", port: 26379, password: "secret"}
          ],
          password: "secret"
        }

        output = capture_logging do
          Sidekiq::RedisClientConnection.create(options)
        end

        refute_includes(options.inspect, "REDACTED")
        assert_includes(output, ':host=>"host1", :port=>26379, :password=>"REDACTED"')
        assert_includes(output, ':host=>"host2", :port=>26379, :password=>"REDACTED"')
        assert_includes(output, ':host=>"host3", :port=>26379, :password=>"REDACTED"')
        assert_includes(output, ':password=>"REDACTED"')
      end

      it "prunes SSL parameters from the logging" do
        options = {
          ssl_params: {
            cert_store: OpenSSL::X509::Store.new
          }
        }

        output = capture_logging do
          Sidekiq::RedisClientConnection.create(options)
        end

        assert_includes(options.inspect, "ssl_params")
        refute_includes(output, "ssl_params")
      end
    end
  end

  describe ".determine_redis_provider" do
    before do
      @old_env = ENV.to_hash
    end

    after do
      ENV.update(@old_env)
    end

    def with_env_var(var, uri, skip_provider = false)
      vars = ["REDISTOGO_URL", "REDIS_PROVIDER", "REDIS_URL"] - [var]
      vars.each do |v|
        next if skip_provider
        ENV[v] = nil
      end
      ENV[var] = uri
      assert_equal uri, Sidekiq::RedisClientConnection.__send__(:determine_redis_provider)
      ENV[var] = nil
    end

    describe "with REDISTOGO_URL and a parallel REDIS_PROVIDER set" do
      it "sets connection URI to the provider" do
        uri = "redis://sidekiq-redis-provider:6379/0"
        provider = "SIDEKIQ_REDIS_PROVIDER"

        ENV["REDIS_PROVIDER"] = provider
        ENV[provider] = uri
        ENV["REDISTOGO_URL"] = "redis://redis-to-go:6379/0"
        with_env_var provider, uri, true

        ENV[provider] = nil
      end
    end

    describe "with REDIS_PROVIDER set" do
      it "rejects URLs in REDIS_PROVIDER" do
        uri = "redis://sidekiq-redis-provider:6379/0"

        ENV["REDIS_PROVIDER"] = uri

        assert_raises RuntimeError do
          Sidekiq::RedisClientConnection.__send__(:determine_redis_provider)
        end

        ENV["REDIS_PROVIDER"] = nil
      end

      it "sets connection URI to the provider" do
        uri = "redis://sidekiq-redis-provider:6379/0"
        provider = "SIDEKIQ_REDIS_PROVIDER"

        ENV["REDIS_PROVIDER"] = provider
        ENV[provider] = uri

        with_env_var provider, uri, true

        ENV[provider] = nil
      end
    end

    describe "with REDIS_URL set" do
      it "sets connection URI to custom uri" do
        with_env_var "REDIS_URL", "redis://redis-uri:6379/0"
      end
    end
  end
end
