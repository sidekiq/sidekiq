# frozen_string_literal: true

require_relative 'helper'
require 'sidekiq/job_logger'

class TestJobLogger < Minitest::Test
  Foo = Class.new
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

    pretty = @logger.formatter = Sidekiq::Logger::Formatters::Pretty.new
    job = {"jid"=>"1234abc", "wrapped"=>"FooWorker", "class"=>"ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper", "tags" => ["bar", "baz"]}
    # this mocks what Processor does
    jl.prepare(job) do
      jl.call(job, 'queue') {}
    end

    a, b = @output.string.lines
    assert a
    assert b

    expected = /pid=#{$$} tid=#{pretty.tid} class=FooWorker jid=1234abc tags=bar,baz/
    assert_match(expected, a)
    assert_match(expected, b)
    assert_match(/#{Time.now.utc.to_date}.+Z pid=#{$$} tid=#{pretty.tid} .+INFO: done/, b)
  end

  def test_delayed_extension
    jl = Sidekiq::JobLogger.new(@logger)
    job = {"class"=>"Sidekiq::Extensions::DelayedClass", "args"=>["---\n- !ruby/class 'TestJobLogger::Foo'\n- :call\n- - bar\n"], "jid"=>"a"}
    jl.prepare(job) do
      jl.call(job, 'queue') {}
    end

    start, done = @output.string.lines
    assert start
    assert done

    expected = /class=TestJobLogger::Foo.call/
    assert_match(expected, start)
    assert_match(expected, done)
  end

  def test_json_output
    # json
    @logger.formatter = Sidekiq::Logger::Formatters::JSON.new
    jl = Sidekiq::JobLogger.new(@logger)
    job = {"jid"=>"1234abc", "wrapped"=>"Wrapper", "class"=>"FooWorker", "bid"=>"b-xyz", "tags" => ["bar", "baz"]}
    # this mocks what Processor does
    jl.prepare(job) do
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
    jl.prepare(job) do
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
    jl.prepare(job) do
      jl.call(job, "queue") do
        assert @logger.info?
      end
    end
    assert @logger.info?
    log_level_warning = @output.string.lines[0]
    assert_match(/WARN: Invalid log level/, log_level_warning)
  end
end
