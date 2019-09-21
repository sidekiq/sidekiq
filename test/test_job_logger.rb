# frozen_string_literal: true

require_relative 'helper'
require 'sidekiq/job_logger'

class TestJobLogger < Minitest::Test
  def setup
    @old = Sidekiq.logger
    @output = StringIO.new
    @logger = Sidekiq::Logger.new(@output)

    Thread.current[:sidekiq_context] = nil
    Thread.current[:sidekiq_tid] = nil
  end

  def teardown
    Thread.current[:sidekiq_context] = nil
    Thread.current[:sidekiq_tid] = nil
  end


  def test_pretty_output
    jl = Sidekiq::JobLogger.new(@logger)

    # pretty
    p = @logger.formatter = Sidekiq::Logger::Formatters::Pretty.new
    job = {"jid"=>"1234abc", "wrapped"=>"FooWorker", "class"=>"Wrapper", "tags" => ["bar", "baz"]}
    # this mocks what Processor does
    jl.with_job_hash_context(job) do
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
    jl.with_job_hash_context(job) do
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

  def reset(io)
    io.truncate(0)
    io.rewind
  end
end
