require_relative 'helper'

class TestRedisConnection < Sidekiq::Test

  describe ".create" do

    it "creates a pooled redis connection" do
      pool = Sidekiq::RedisConnection.create
      assert_equal Redis, pool.checkout.class
    end

    describe "network_timeout" do
      it "sets a custom network_timeout if specified" do
        pool = Sidekiq::RedisConnection.create(:network_timeout => 8)
        redis = pool.checkout

        assert_equal 8, redis.client.timeout
      end

      it "uses the default network_timeout if none specified" do
        pool = Sidekiq::RedisConnection.create
        redis = pool.checkout

        assert_equal 5, redis.client.timeout
      end
    end

    describe "namespace" do
      it "uses a given :namespace" do
        pool = Sidekiq::RedisConnection.create(:namespace => "xxx")
        assert_equal "xxx", pool.checkout.namespace
      end

      it "uses given :namespace over :namespace from Sidekiq.options" do
        Sidekiq.options[:namespace] = "xxx"
        pool = Sidekiq::RedisConnection.create(:namespace => "yyy")
        assert_equal "yyy", pool.checkout.namespace
      end
    end

    describe "socket path" do
      it "uses a given :path" do
        pool = Sidekiq::RedisConnection.create(:path => "/var/run/redis.sock")
        assert_equal "unix", pool.checkout.client.scheme
        assert_equal "redis:///var/run/redis.sock/0", pool.checkout.client.id
      end

      it "uses a given :path and :db" do
        pool = Sidekiq::RedisConnection.create(:path => "/var/run/redis.sock", :db => 8)
        assert_equal "unix", pool.checkout.client.scheme
        assert_equal "redis:///var/run/redis.sock/8", pool.checkout.client.id
      end
    end

    describe "pool_timeout" do
      it "uses a given :timeout over the default of 1" do
        pool = Sidekiq::RedisConnection.create(:pool_timeout => 5)

        assert_equal 5, pool.instance_eval{ @timeout }
      end

      it "uses the default timeout of 1 if no override" do
        pool = Sidekiq::RedisConnection.create

        assert_equal 1, pool.instance_eval{ @timeout }
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

    def with_env_var(var, uri, skip_provider=false)
      vars = ['REDISTOGO_URL', 'REDIS_PROVIDER', 'REDIS_URL'] - [var]
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
        uri = 'redis://sidekiq-redis-provider:6379/0'
        provider = 'SIDEKIQ_REDIS_PROVIDER'

        ENV['REDIS_PROVIDER'] = provider
        ENV[provider] = uri
        ENV['REDISTOGO_URL'] = 'redis://redis-to-go:6379/0'
        with_env_var provider, uri, true

        ENV[provider] = nil
      end
    end

    describe "with REDIS_PROVIDER set" do
      it "sets connection URI to the provider" do
        uri = 'redis://sidekiq-redis-provider:6379/0'
        provider = 'SIDEKIQ_REDIS_PROVIDER'

        ENV['REDIS_PROVIDER'] = provider
        ENV[provider] = uri

        with_env_var provider, uri, true

        ENV[provider] = nil
      end
    end

    describe "with REDIS_URL set" do
      it "sets connection URI to custom uri" do
        with_env_var 'REDIS_URL', 'redis://redis-uri:6379/0'
      end
    end

  end
end
