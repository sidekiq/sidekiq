require 'helper'
require 'sidekiq/redis_connection'

class TestRedisConnection < MiniTest::Unit::TestCase

  describe ".create" do

    def with_env_var(var, uri, skip_provider=false)
      vars = ['REDISTOGO_URL', 'REDIS_PROVIDER', 'REDIS_URL'] - [var]
      vars.each do |v|
        next if skip_provider
        ENV[v] = nil
      end
      ENV[var] = uri
      assert_equal uri, Sidekiq::RedisConnection.determine_redis_provider
      ENV[var] = nil
    end

    describe "with REDISTOGO_URL set" do
      it "sets connection URI to RedisToGo" do
        with_env_var 'REDISTOGO_URL', 'redis://redis-to-go:6379/0'
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
