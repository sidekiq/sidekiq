require_relative "helper"
require "sidekiq/job_retry"

class NewWorker
  include Sidekiq::Job

  sidekiq_class_attribute :exhausted_called, :exhausted_job, :exhausted_exception

  sidekiq_retries_exhausted do |job, e|
    self.exhausted_called = true
    self.exhausted_job = job
    self.exhausted_exception = e
  end
end

class OldWorker
  include Sidekiq::Job

  sidekiq_class_attribute :exhausted_called, :exhausted_job, :exhausted_exception

  sidekiq_retries_exhausted do |job|
    self.exhausted_called = true
    self.exhausted_job = job
  end
end

describe "sidekiq_retries_exhausted" do
  def cleanup
    [NewWorker, OldWorker].each do |worker_class|
      worker_class.exhausted_called = nil
      worker_class.exhausted_job = nil
      worker_class.exhausted_exception = nil
    end
  end

  before do
    @config = Sidekiq::Config.new
    cleanup
  end

  after do
    cleanup
  end

  def new_worker
    @new_worker ||= NewWorker.new
  end

  def old_worker
    @old_worker ||= OldWorker.new
  end

  def handler
    @handler ||= Sidekiq::JobRetry.new(@config)
  end

  def job(options = {})
    @job ||= Sidekiq.dump_json({"class" => "Bob", "args" => [1, 2, "foo"]}.merge(options))
  end

  it "does not run exhausted block when job successful on first run" do
    handler.local(new_worker, job("retry" => 2), "default") do
      # successful
    end

    refute NewWorker.exhausted_called
  end

  it "does not run exhausted block when job successful on last retry" do
    handler.local(new_worker, job("retry_count" => 0, "retry" => 1), "default") do
      # successful
    end

    refute NewWorker.exhausted_called
  end

  it "does not run exhausted block when retries not exhausted yet" do
    assert_raises RuntimeError do
      handler.local(new_worker, job("retry" => 1), "default") do
        raise "kerblammo!"
      end
    end

    refute NewWorker.exhausted_called
  end

  it "runs exhausted block when retries exhausted" do
    assert_raises RuntimeError do
      handler.local(new_worker, job("retry_count" => 0, "retry" => 1), "default") do
        raise "kerblammo!"
      end
    end

    assert NewWorker.exhausted_called
  end

  it "passes job and exception to retries exhausted block" do
    raised_error = assert_raises RuntimeError do
      handler.local(new_worker, job("retry_count" => 0, "retry" => 1), "default") do
        raise "kerblammo!"
      end
    end
    raised_error = raised_error.cause

    assert new_worker.exhausted_called
    assert_equal raised_error.message, new_worker.exhausted_job["error_message"]
    assert_equal raised_error, new_worker.exhausted_exception
  end

  it "passes job to retries exhausted block" do
    raised_error = assert_raises RuntimeError do
      handler.local(old_worker, job("retry_count" => 0, "retry" => 1), "default") do
        raise "kerblammo!"
      end
    end
    raised_error = raised_error.cause

    assert old_worker.exhausted_called
    assert_equal raised_error.message, old_worker.exhausted_job["error_message"]
    assert_nil new_worker.exhausted_exception
  end

  it "allows global failure handlers" do
    class Foobar
      include Sidekiq::Job
    end

    exhausted_job = nil
    exhausted_exception = nil
    @config.death_handlers.clear
    @config.death_handlers << proc do |job, ex|
      exhausted_job = job
      exhausted_exception = ex
    end
    f = Foobar.new
    raised_error = assert_raises RuntimeError do
      handler.local(f, job("retry_count" => 0, "retry" => 1), "default") do
        raise "kerblammo!"
      end
    end
    raised_error = raised_error.cause

    assert exhausted_job
    assert_equal raised_error, exhausted_exception
  end
end
