# frozen_string_literal: true

require_relative 'helper'
require 'sidekiq/logger'

class TestLogger < Minitest::Test
  def setup
    @output = StringIO.new
    @logger = Sidekiq::Logger.new(@output)

    Sidekiq.log_formatter = nil
    Thread.current[:sidekiq_context] = nil
    Thread.current[:sidekiq_tid] = nil
  end

  def teardown
    Sidekiq.log_formatter = nil
    Thread.current[:sidekiq_context] = nil
    Thread.current[:sidekiq_tid] = nil
  end

  def test_default_log_formatter
    assert_kind_of Sidekiq::Logger::Formatters::Pretty, Sidekiq::Logger.new(@output).formatter
  end

  def test_heroku_log_formatter
    begin
      ENV['DYNO'] = 'dyno identifier'
      assert_kind_of Sidekiq::Logger::Formatters::WithoutTimestamp, Sidekiq::Logger.new(@output).formatter
    ensure
      ENV['DYNO'] = nil
    end
  end

  def test_json_log_formatter
    Sidekiq.log_formatter = Sidekiq::Logger::Formatters::JSON.new

    assert_kind_of Sidekiq::Logger::Formatters::JSON, Sidekiq::Logger.new(@output).formatter
  end

  def test_with_context
    subject = Sidekiq::Context
    assert_equal({}, subject.current)

    subject.with(a: 1) do
      assert_equal({ a: 1 }, subject.current)
    end

    assert_equal({}, subject.current)
  end

  def test_nested_contexts
    subject = Sidekiq::Context
    assert_equal({}, subject.current)

    subject.with(a: 1) do
      assert_equal({ a: 1 }, subject.current)

      subject.with(b: 2, c: 3) do
        assert_equal({ a: 1, b: 2, c: 3 }, subject.current)
      end

      assert_equal({ a: 1 }, subject.current)
    end

    assert_equal({}, subject.current)
  end

  def test_formatted_output
    @logger.info("hello world")
    assert_match(/INFO: hello world/, @output.string)
    reset(@output)

    formats = [ Sidekiq::Logger::Formatters::Pretty,
                Sidekiq::Logger::Formatters::WithoutTimestamp,
                Sidekiq::Logger::Formatters::JSON, ]
    formats.each do |fmt|
      @logger.formatter = fmt.new
      Sidekiq::Context.with(class: 'HaikuWorker', bid: 'b-1234abc') do
        @logger.info("hello context")
      end
      assert_match(/INFO/, @output.string)
      assert_match(/hello context/, @output.string)
      assert_match(/b-1234abc/, @output.string)
      reset(@output)
    end
  end

  def test_json_output_is_parsable
    @logger.formatter = Sidekiq::Logger::Formatters::JSON.new

    @logger.debug("boom")
    Sidekiq::Context.with(class: 'HaikuWorker', jid: '1234abc') do
      @logger.info("json format")
    end
    a, b = @output.string.lines
    hash = JSON.parse(a)
    keys = hash.keys.sort
    assert_equal ["lvl", "msg", "pid", "tid", "ts"], keys
    assert_nil hash["ctx"]
    assert_equal hash["lvl"], "DEBUG"

    hash = JSON.parse(b)
    keys = hash.keys.sort
    assert_equal ["ctx", "lvl", "msg", "pid", "tid", "ts"], keys
    refute_nil hash["ctx"]
    assert_equal "1234abc", hash["ctx"]["jid"]
    assert_equal "INFO", hash["lvl"]
  end

  def test_forwards_logger_kwargs
    assert_silent do
      logger = Sidekiq::Logger.new('/dev/null', level: Logger::INFO)

      assert_equal Logger::INFO, logger.level
    end
  end

  def test_log_level_query_methods
    logger = Sidekiq::Logger.new('/dev/null', level: Logger::INFO)

    refute_predicate logger, :debug?
    assert_predicate logger, :info?
    assert_predicate logger, :warn?

    logger.level = Logger::WARN
    refute_predicate logger, :info?
    assert_predicate logger, :warn?
  end

  def reset(io)
    io.truncate(0)
    io.rewind
  end
end
