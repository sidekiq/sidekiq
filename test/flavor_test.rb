# frozen_string_literal: true

require_relative "helper"
require "sidekiq/api"

class FlavorTest < Minitest::Test
  class Job
    include Sidekiq::Job

    def perform(*args)
      args
    end
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

  class Ruby
    def name = "rb"
    def to_j(a) = [Base64.urlsafe_encode64(Marshal.dump(a))]
    def from_j(a) = Marshal.load(Base64.urlsafe_decode64(a.first))
  end

  def test_rb
    Sidekiq.default_configuration.flavor.add(Ruby.new)
    q = Sidekiq::Queue.new
    obj = Custom.new(456)

    Job.perform_async(123, obj)
    job = q.first
    assert_equal [123, obj.to_s], job["args"]
    q.clear

    Job.set(flavor: "rb").perform_async(123, obj)
    job = q.first
    assert_equal [123, obj], job["args"]
    q.clear

    Job.set(flavor: "rb").perform_async(123, k1: "foo", k2: "bar")
    job = q.first
    assert_equal [123, k1: "foo", k2: "bar"], job["args"]
    q.clear

    j = Job.new
    j.perform(*job["args"])
    # pp res
  end
end
