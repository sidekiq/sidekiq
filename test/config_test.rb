# frozen_string_literal: true

require_relative "helper"

describe Sidekiq::Config do
  before do
    @config = reset!
  end

  it "provides a default size" do
    @config.redis = {}
    assert_equal 10, @config.redis_pool.size
  end

  it "allows custom sizing" do
    @config.redis = {size: 3}
    assert_equal 3, @config.redis_pool.size
  end

  it "merges repeated redis= calls made before the pool is created" do
    @config.redis = {size: 2}
    @config.redis = {size: 3}
    assert_equal 3, @config.redis_pool.size
  end

  it "raises when redis= runs after the pool was created" do
    @config.redis = {}
    @config.redis_pool

    error = assert_raises(RuntimeError) { @config.redis = {size: 3} }
    assert_includes error.message, "Configure Redis before anything uses Sidekiq"
    assert_includes error.message, "config_test.rb"
  end

  it "keeps #inspect output manageable" do
    assert_operator @config.inspect.size, :<=, 500
    refute_match(/death_handlers/, @config.inspect)
    refute_match(/error_handlers/, @config.inspect)
  end

  describe "default logger formatter" do
    def with_env(key, value)
      original = ENV[key]
      value.nil? ? ENV.delete(key) : ENV[key] = value
      yield
    ensure
      original.nil? ? ENV.delete(key) : ENV[key] = original
    end

    it "uses WithoutTimestamp when running on Heroku (DYNO env var set)" do
      with_env("DYNO", "web.1") do
        cfg = Sidekiq::Config.new
        assert_instance_of Sidekiq::Logger::Formatters::WithoutTimestamp, cfg.logger.formatter
      end
    end

    it "uses Pretty when not running on Heroku" do
      with_env("DYNO", nil) do
        cfg = Sidekiq::Config.new
        assert_instance_of Sidekiq::Logger::Formatters::Pretty, cfg.logger.formatter
      end
    end
  end

  describe "#logger=" do
    it "silences the existing logger by raising the level to FATAL when set to nil" do
      cfg = Sidekiq::Config.new
      existing = cfg.logger
      refute_equal Logger::FATAL, existing.level

      cfg.logger = nil

      assert_same existing, cfg.logger, "expected logger= nil to keep the existing logger instance"
      assert_equal Logger::FATAL, cfg.logger.level
    end
  end
end
