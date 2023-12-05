# frozen_string_literal: true

require "bundler/setup"
Bundler.require(:default, :test)

require "minitest/pride"
require "maxitest/autorun"
require "maxitest/threads"
require "datadog/ci"
require "ddtrace/auto_instrument"

$TESTING = true
# disable minitest/parallel threads
ENV["MT_CPU"] = "0"
ENV["N"] = "0"
# Disable any stupid backtrace cleansers
ENV["BACKTRACE"] = "1"

if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start do
    enable_coverage :branch
    add_filter "/test/"
    add_filter "/myapp/"
    minimum_coverage 90
  end
end

# Configure default Minitest integration
Datadog.configure do |c|
  c.service = "sidekiq"
  c.ci.enabled = true
  # c.ci.experimental_test_suite_level_visibility_enabled = true
  c.ci.instrument :minitest
  c.diagnostics.startup_logs.enabled = false
end

ENV["REDIS_URL"] ||= "redis://localhost/15"
NULL_LOGGER = Logger.new(IO::NULL)

def reset!
  # tidy up any open but unreferenced Redis connections so we don't run out of file handles
  if Sidekiq.default_configuration.instance_variable_defined?(:@redis)
    existing_pool = Sidekiq.default_configuration.instance_variable_get(:@redis)
    existing_pool&.shutdown(&:close)
  end

  RedisClient.new(url: ENV["REDIS_URL"]).call("flushall")
  cfg = Sidekiq::Config.new
  cfg[:backtrace_cleaner] = Sidekiq::Config::DEFAULTS[:backtrace_cleaner]
  cfg.logger = NULL_LOGGER
  cfg.logger.level = Logger::WARN
  Sidekiq.instance_variable_set :@config, cfg
  cfg
end

def capture_logging(cfg, lvl = Logger::INFO)
  old = cfg.logger
  begin
    out = StringIO.new
    logger = ::Logger.new(out)
    logger.level = lvl
    cfg.logger = logger
    yield logger
    out.string
  ensure
    cfg.logger = old
  end
end

Signal.trap("TTIN") do
  Thread.list.each do |thread|
    puts "Thread TID-#{(thread.object_id ^ ::Process.pid).to_s(36)} #{thread.name}"
    if thread.backtrace
      puts thread.backtrace.join("\n")
    else
      puts "<no backtrace available>"
    end
  end
end

# module Minitest
#   class << self
#     alias_method :old_run, :run

#     def run(args = [])
#       p "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
#       p "START TEST SESSION"
#       test_session = Datadog::CI.start_test_session(
#         service_name: "sidekiq",
#         tags: {
#           "test.framework" => "minitest",
#           "test.type" => "test"
#         }
#       )

#       p "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
#       p "START TEST MODULE"
#       test_module = Datadog::CI.start_test_module("minitest-run")

#       result = old_run

#       p "TEST MODULE NOW IS"
#       p test_module

#       if test_module
#         p "FINISHING TEST MODULE"
#         if result
#           test_module.passed!
#         else
#           test_module.failed!
#         end

#         test_module.finish
#       end

#       sleep(2)

#       p "TEST SESSION NOW IS"
#       p test_session

#       if test_session
#         p "FINISHING TEST SESSION"
#         if result
#           test_session.passed!
#         else
#           test_session.failed!
#         end

#         test_session.finish
#       end

#       result
#     end
#   end
# end

# class Minitest::Runnable
#   class << self
#     alias_method :old_run, :run

#     def run reporter, options = {}
#       # see cli_test.rb: every describe block is a separate runnable but in our
#       # current definition they must all belong to a single test suite
#       method_name = runnable_methods.first
#       test_suite = nil

#       if method_name
#         path, = instance_method(method_name).source_location
#         test_suite_name = Pathname.new(path.to_s).relative_path_from(Pathname.pwd).to_s

#         p "START TEST SUITE: #{test_suite_name}"
#         test_suite = Datadog::CI.start_test_suite(test_suite_name)
#       end

#       result = old_run(reporter, options)

#       if test_suite
#         p "FINISHING TEST SUITE: #{test_suite}"
#         # reporter.passed? check is wrong, I need to check whether one of the runnables failed or not
#         if reporter.passed?
#           test_suite.passed!
#         else
#           test_suite.failed!
#         end
#         test_suite.finish
#       end

#       result
#     end
#   end
# end
