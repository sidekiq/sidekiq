# encoding: utf-8
require_relative 'helper'
require 'sidekiq/middleware/server/retry_jobs'

class TestRetryExhausted < Sidekiq::Test
  describe 'sidekiq_retries_exhausted' do
    class NewWorker
      include Sidekiq::Worker

      class_attribute :exhausted_called, :exhausted_job, :exhausted_exception

      sidekiq_retries_exhausted do |job, e|
        self.exhausted_called = true
        self.exhausted_job = job
        self.exhausted_exception = e
      end
    end

    class OldWorker
      include Sidekiq::Worker

      class_attribute :exhausted_called, :exhausted_job, :exhausted_exception

      sidekiq_retries_exhausted do |job|
        self.exhausted_called = true
        self.exhausted_job = job
      end
    end

    def cleanup
      [NewWorker, OldWorker].each do |worker_class|
        worker_class.exhausted_called = nil
        worker_class.exhausted_job = nil
        worker_class.exhausted_exception = nil
      end
    end

    before do
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

    def handler(options={})
      @handler ||= Sidekiq::Middleware::Server::RetryJobs.new(options)
    end

    def job(options={})
      @job ||= {'class' => 'Bob', 'args' => [1, 2, 'foo']}.merge(options)
    end

    it 'does not run exhausted block when job successful on first run' do
      handler.call(new_worker, job('retry' => 2), 'default') do
        # successful
      end

      refute NewWorker.exhausted_called?
    end

    it 'does not run exhausted block when job successful on last retry' do
      handler.call(new_worker, job('retry_count' => 0, 'retry' => 1), 'default') do
        # successful
      end

      refute NewWorker.exhausted_called?
    end

    it 'does not run exhausted block when retries not exhausted yet' do
      assert_raises RuntimeError do
        handler.call(new_worker, job('retry' => 1), 'default') do
          raise 'kerblammo!'
        end
      end

      refute NewWorker.exhausted_called?
    end

    it 'runs exhausted block when retries exhausted' do
      assert_raises RuntimeError do
        handler.call(new_worker, job('retry_count' => 0, 'retry' => 1), 'default') do
          raise 'kerblammo!'
        end
      end

      assert NewWorker.exhausted_called?
    end


    it 'passes job and exception to retries exhausted block' do
      raised_error = assert_raises RuntimeError do
        handler.call(new_worker, job('retry_count' => 0, 'retry' => 1), 'default') do
          raise 'kerblammo!'
        end
      end

      assert new_worker.exhausted_called?
      assert_equal raised_error.message, new_worker.exhausted_job['error_message']
      assert_equal raised_error, new_worker.exhausted_exception
    end

    it 'passes job to retries exhausted block' do
      raised_error = assert_raises RuntimeError do
        handler.call(old_worker, job('retry_count' => 0, 'retry' => 1), 'default') do
          raise 'kerblammo!'
        end
      end

      assert old_worker.exhausted_called?
      assert_equal raised_error.message, old_worker.exhausted_job['error_message']
      assert_equal nil, new_worker.exhausted_exception
    end

    it 'allows a global default handler' do
      begin
        class Foobar
          include Sidekiq::Worker
        end

        exhausted_job = nil
        exhausted_exception = nil
        Sidekiq.default_retries_exhausted = lambda do |job, ex|
          exhausted_job = job
          exhausted_exception = ex
        end
        f = Foobar.new
        raised_error = assert_raises RuntimeError do
          handler.call(f, job('retry_count' => 0, 'retry' => 1), 'default') do
            raise 'kerblammo!'
          end
        end

        assert exhausted_job
        assert_equal raised_error, exhausted_exception
      ensure
        Sidekiq.default_retries_exhausted = nil
      end
    end
  end
end
