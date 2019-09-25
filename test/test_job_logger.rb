# frozen_string_literal: true

require_relative 'helper'
require 'sidekiq/job_logger'

class TestJobLogger < Minitest::Test
  def setup
    @old = Sidekiq.logger
    @output = StringIO.new
    @logger = Sidekiq::Logger.new(@output, level: :info)
    Sidekiq.logger = @logger

    Thread.current[:sidekiq_context] = nil
    Thread.current[:sidekiq_tid] = nil
  end

  def teardown
    Thread.current[:sidekiq_context] = nil
    Thread.current[:sidekiq_tid] = nil
    Sidekiq.logger = @old
  end

  def test_pretty_output
    jl = Sidekiq::JobLogger.new(@logger)

    # pretty
    p = @logger.formatter = Sidekiq::Logger::Formatters::Pretty.new
    job = {"jid"=>"1234abc", "wrapped"=>"FooWorker", "class"=>"Wrapper", "tags" => ["bar", "baz"]}
    # this mocks what Processor does
    jl.with_job_hash_context_and_log_level(job) do
      jl.call(job, 'queue') {}
    end

    a, b = @output.string.lines
    assert a
    assert b

    expected = /pid=#{$$} tid=#{p.tid} class=FooWorker jid=1234abc tags=bar,baz/
    assert_match(expected, a)
    assert_match(expected, b)
    assert_match(/#{Time.now.utc.to_date}.+Z pid=#{$$} tid=#{p.tid} .+INFO: done/, b)
  end

  def test_json_output
    # json
    @logger.formatter = Sidekiq::Logger::Formatters::JSON.new
    jl = Sidekiq::JobLogger.new(@logger)
    job = {"jid"=>"1234abc", "wrapped"=>"Wrapper", "class"=>"FooWorker", "bid"=>"b-xyz", "tags" => ["bar", "baz"]}
    # this mocks what Processor does
    jl.with_job_hash_context_and_log_level(job) do
      jl.call(job, 'queue') {}
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

  def test_custom_log_level
    jl = Sidekiq::JobLogger.new(@logger)
    job = {"class"=>"FooWorker", "log_level"=>"debug"}

    assert @logger.info?
    jl.with_job_hash_context_and_log_level(job) do
      jl.call(job, "queue") do
        assert @logger.debug?
        @logger.debug("debug message")
      end
    end
    assert @logger.info?

    a, b, c = @output.string.lines
    assert_match(/INFO: start/, a)
    assert_match(/DEBUG: debug message/, b)
    assert_match(/INFO: done/, c)
  end

  def test_custom_log_level_uses_default_log_level_for_invalid_value
    jl = Sidekiq::JobLogger.new(@logger)
    job = {"class"=>"FooWorker", "log_level"=>"non_existent"}

    assert @logger.info?
    jl.with_job_hash_context_and_log_level(job) do
      jl.call(job, "queue") do
        assert @logger.info?
      end
    end
    assert @logger.info?
    log_level_warning = @output.string.lines[0]
    assert_match(/INFO: Invalid log level/, log_level_warning)
  end

  def reset(io)
    io.truncate(0)
    io.rewind
  end
end
