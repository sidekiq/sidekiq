# frozen_string_literal: true

require_relative "helper"
require "sidekiq/job_logger"

describe "Job logger" do
  before do
    @output = StringIO.new
    @logger = Sidekiq::Logger.new(@output, level: :info)
    @logger.formatter = Sidekiq::Logger::Formatters::Pretty.new

    @cfg = reset!
    @cfg.logger = @logger

    Thread.current[:sidekiq_context] = nil
    Thread.current[:sidekiq_tid] = nil
  end

  after do
    Thread.current[:sidekiq_context] = nil
    Thread.current[:sidekiq_tid] = nil
  end

  it "allows output to be disabled" do
    @logger.formatter = Sidekiq::Logger::Formatters::Pretty.new
    @cfg[:skip_default_job_logging] = true

    jl = Sidekiq::JobLogger.new(@cfg)
    @logger.info "mike"
    job = {"jid" => "1234abc", "wrapped" => "FooJob", "class" => "Wrapper", "tags" => ["bar", "baz"]}
    jl.prepare(job) do
      jl.call(job, "queue") {}
    end

    a, b = @output.string.lines
    assert_match(/mike/, a)
    refute b
  end

  it "tests pretty output" do
    jl = Sidekiq::JobLogger.new(@cfg)

    # pretty
    p = @logger.formatter = Sidekiq::Logger::Formatters::Pretty.new
    job = {"jid" => "1234abc", "wrapped" => "FooJob", "class" => "Wrapper", "tags" => ["bar", "baz"]}
    # this mocks what Processor does
    jl.prepare(job) do
      jl.call(job, "queue") {}
    end

    @output.string.lines.each do |a|
      assert_match(/pid=#{$$}/, a)
      assert_match(/tid=#{p.tid}/, a)
      assert_match(/class=FooJob/, a)
      assert_match(/jid=1234abc/, a)
      assert_match(/tags=bar,baz/, a)
    end
  end

  it "tests json output" do
    # json
    @logger.formatter = Sidekiq::Logger::Formatters::JSON.new
    jl = Sidekiq::JobLogger.new(@cfg)
    job = {"jid" => "1234abc", "wrapped" => "Wrapper", "class" => "FooJob", "bid" => "b-xyz", "tags" => ["bar", "baz"]}
    # this mocks what Processor does
    jl.prepare(job) do
      jl.call(job, "queue") {}
    end
    a, b = @output.string.lines
    assert a
    assert b
    hsh = JSON.parse(a)
    keys = hsh.keys.sort
    assert_equal(["ctx", "lvl", "msg", "pid", "tid", "ts"], keys)
    keys = hsh["ctx"].keys.sort
    assert_equal(["bid", "class", "jid", "tags"], keys)
  end

  it "tests custom log level" do
    jl = Sidekiq::JobLogger.new(@cfg)
    job = {"class" => "FooJob", "log_level" => "debug"}

    assert @logger.info?
    jl.prepare(job) do
      jl.call(job, "queue") do
        assert @logger.debug?
        @logger.debug("debug message")
      end
    end
    assert @logger.info?

    a, b, c = @output.string.lines
    assert_match(/INFO.+: start/, a)
    assert_match(/DEBUG.+: debug message/, b)
    assert_match(/INFO.+: done/, c)
  end

  it "tests custom log attributes" do
    @cfg.logged_job_attributes << "trace_id"
    jl = Sidekiq::JobLogger.new(@cfg)
    job = {"class" => "FooJob", "trace_id" => "xxx"}
    jl.prepare(job) do
      assert_equal Sidekiq::Context.current[:trace_id], "xxx"
    end
    job = {"class" => "FooJob"}
    jl.prepare(job) do
      refute(Sidekiq::Context.current.key?(:trace_id))
    end
  end

  it "tests custom logger with non numeric levels" do
    @logger = Logger.new(@output, level: :info)
    @cfg.logger = @logger

    jl = Sidekiq::JobLogger.new(@cfg)
    job = {"class" => "FooJob", "log_level" => "debug"}

    assert @logger.info?
    refute @logger.debug?
    jl.prepare(job) do
      jl.call(job, "queue") do
        assert @logger.debug?
      end
    end
    assert @logger.info?
    refute @logger.debug?

    jl.prepare(job) do
      jl.call(job, "queue") do
        assert @logger.debug?
      end
    end
  end
end
