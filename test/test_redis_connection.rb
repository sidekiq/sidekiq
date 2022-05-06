# frozen_string_literal: true

require_relative "helper"
require "sidekiq/cli"

describe Sidekiq::RedisConnection do
  describe "create" do
    before do
      Sidekiq.options = Sidekiq::DEFAULTS.dup
      @old = ENV["REDIS_URL"]
      ENV["REDIS_URL"] = "redis://localhost/15"
    end

    after do
      ENV["REDIS_URL"] = @old
    end

    # To support both redis-rb 3.3.x #client and 4.0.x #_client
    def client_for(redis)
      if redis.respond_to?(:_client)
        redis._client
      else
        redis.client
      end
    end

    def config_for(redis)
      client = client_for(redis)
      if client.respond_to?(:config)
        client.config
      else
        client
      end
    end

    def self.redis_client?
      Sidekiq::RedisConnection.adapter == Sidekiq::RedisConnection::RedisClientAdapter
    end

    if redis_client?
      def client_class
        Sidekiq::RedisConnection::RedisClientAdapter::CompatClient
      end
    else
      def client_class
        Redis
      end
    end

    it "creates a pooled redis connection" do
      pool = Sidekiq::RedisConnection.create
      assert_equal client_class, pool.checkout.class
    end

    # Readers for these ivars should be available in the next release of
    # `connection_pool`, until then we need to reach into the internal state to
    # verify the setting.
    describe "size" do
      def client_connection(*args)
        Sidekiq.stub(:server?, nil) do
          Sidekiq::RedisConnection.create(*args)
        end
      end

      def server_connection(*args)
        Sidekiq.stub(:server?, "constant") do
          Sidekiq::RedisConnection.create(*args)
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
      pool = Sidekiq::RedisConnection.create(id: nil)
      assert_equal client_class, pool.checkout.class
      client = client_for(pool.checkout)
      if self.class.redis_client?
        assert_nil client.id
      else
        assert_equal "redis://localhost:6379/15", client.id
      end
    end

    describe "network_timeout" do
      it "sets a custom network_timeout if specified" do
        pool = Sidekiq::RedisConnection.create(network_timeout: 8)
        redis = pool.checkout

        assert_equal 8, client_for(redis).read_timeout
      end

      it "uses the default network_timeout if none specified" do
        pool = Sidekiq::RedisConnection.create
        redis = pool.checkout

        if self.class.redis_client?
          assert_equal 1.0, client_for(redis).read_timeout
        else
          assert_equal 5, client_for(redis).read_timeout
        end
      end
    end

    describe "namespace" do
      if redis_client?
        it "isn't supported" do
          Kernel.stub(:exit, ->(code) { raise "Exited #{code}" }) do
            output = capture_logging do
              error = assert_raises RuntimeError do
                Sidekiq::RedisConnection.create(namespace: "xxx")
              end
              assert_includes error.message, "Exited -127"
            end
            assert_includes output, "Your Redis configuration uses the namespace 'xxx' but this feature isn't supported by redis-client"
          end
        end
      else
        it "uses a given :namespace set by a symbol key" do
          pool = Sidekiq::RedisConnection.create(namespace: "xxx")
          assert_equal "xxx", pool.checkout.namespace
        end

        it "uses a given :namespace set by a string key" do
          pool = Sidekiq::RedisConnection.create("namespace" => "xxx")
          assert_equal "xxx", pool.checkout.namespace
        end

        it "uses given :namespace over :namespace from Sidekiq.options" do
          Sidekiq.options[:namespace] = "xxx"
          pool = Sidekiq::RedisConnection.create(namespace: "yyy")
          assert_equal "yyy", pool.checkout.namespace
        end
      end
    end

    describe "socket path" do
      it "uses a given :path" do
        pool = Sidekiq::RedisConnection.create(path: "/var/run/redis.sock")
        config = config_for(pool.checkout)
        assert_equal "/var/run/redis.sock", config.path
      end

      it "uses a given :path and :db" do
        pool = Sidekiq::RedisConnection.create(path: "/var/run/redis.sock", db: 8)
        config = config_for(pool.checkout)
        assert_equal "/var/run/redis.sock", config.path
        assert_equal 8, config.db
      end
    end

    describe "pool_timeout" do
      it "uses a given :timeout over the default of 1" do
        pool = Sidekiq::RedisConnection.create(pool_timeout: 5)

        assert_equal 5, pool.instance_eval { @timeout }
      end

      it "uses the default timeout of 1 if no override" do
        pool = Sidekiq::RedisConnection.create

        assert_equal 1, pool.instance_eval { @timeout }
      end
    end

    describe "driver" do
      if redis_client?
        it "uses ruby driver by default" do
          pool = Sidekiq::RedisConnection.create
          config = config_for(pool.checkout)

          assert_equal RedisClient::RubyConnection, config.driver
        end
      else
        it "uses redis' ruby driver" do
          pool = Sidekiq::RedisConnection.create
          redis = pool.checkout

          assert_equal Redis::Connection::Ruby, redis.instance_variable_get(:@client).driver
        end

        it "uses redis' default driver if there are many available" do
          redis_driver = Object.new
          Redis::Connection.drivers << redis_driver

          pool = Sidekiq::RedisConnection.create
          redis = pool.checkout

          assert_equal redis_driver, redis.instance_variable_get(:@client).driver
        ensure
          Redis::Connection.drivers.pop
        end

        it "uses a given :driver" do
          redis_driver = Object.new
          pool = Sidekiq::RedisConnection.create(driver: redis_driver)
          redis = pool.checkout

          assert_equal redis_driver, redis.instance_variable_get(:@client).driver
        end
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
          Sidekiq::RedisConnection.create(options)
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
          Sidekiq::RedisConnection.create(options)
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
      assert_equal uri, Sidekiq::RedisConnection.__send__(:determine_redis_provider)
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
          Sidekiq::RedisConnection.__send__(:determine_redis_provider)
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
