# frozen_string_literal: true

require_relative "helper"
require "sidekiq/api"

class FlavorTest < Minitest::Test
  class Job
    include Sidekiq::Job
  end

  def setup
    @prev = Sidekiq::Config::DEFAULTS[:on_complex_arguments]
    Sidekiq::Config::DEFAULTS[:on_complex_arguments] = false
  end

  def teardown
    Sidekiq::Config::DEFAULTS[:on_complex_arguments] = @prev
  end

  class Custom
    attr_reader :x
    def initialize(x)
      @x = x
    end

    def ==(other)
      other.class == self.class && other.x == x
    end
  end

  def test_defaults
    obj = Custom.new(456)
    Job.perform_async(123, obj)
    job = Sidekiq::Queue.new.first
    assert_equal [123, obj.to_s], job["args"]
  end

  def test_marshal
    obj = Custom.new(456)
    Job.set(flavor: "marshal").perform_async(123, obj)
    job = Sidekiq::Queue.new.first
    assert_equal [123, obj], job["args"]
  end
end
