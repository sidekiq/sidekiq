# encoding: utf-8
# frozen_string_literal: true
require_relative 'helper'
require 'sidekiq/scheduled'
require 'sidekiq/job_retry'
require 'sidekiq/api'

describe Sidekiq::JobRetry do
  describe 'middleware' do
    class SomeWorker
      include Sidekiq::Worker
    end

    class BadErrorMessage < StandardError
      def message
        raise "Ahhh, this isn't supposed to happen"
      end
    end

    before do
      Sidekiq.redis {|c| c.flushdb }
    end

    def worker
      @worker ||= SomeWorker.new
    end

    def handler(options={})
      @handler ||= Sidekiq::JobRetry.new(options)
    end

    def jobstr(options={})
      Sidekiq.dump_json({ 'class' => 'Bob', 'args' => [1,2,'foo'], 'retry' => true }.merge(options))
    end

    def job
      Sidekiq::RetrySet.new.first
    end

    it 'retries with a nil worker' do
      assert_raises RuntimeError do
        handler.global(jobstr, 'default') do
          raise "boom"
        end
      end
      assert_equal 1, Sidekiq::RetrySet.new.size
    end

    it 'allows disabling retry' do
      assert_raises RuntimeError do
        handler.local(worker, jobstr('retry' => false), 'default') do
          raise "kerblammo!"
        end
      end
      assert_equal 0, Sidekiq::RetrySet.new.size
    end

    it 'allows a numeric retry' do
      assert_raises RuntimeError do
        handler.local(worker, jobstr('retry' => 2), 'default') do
          raise "kerblammo!"
        end
      end
      assert_equal 1, Sidekiq::RetrySet.new.size
      assert_equal 0, Sidekiq::DeadSet.new.size
    end

    it 'allows 0 retry => no retry and dead queue' do
      assert_raises RuntimeError do
        handler.local(worker, jobstr('retry' => 0), 'default') do
          raise "kerblammo!"
        end
      end
      assert_equal 0, Sidekiq::RetrySet.new.size
      assert_equal 1, Sidekiq::DeadSet.new.size
    end

    it 'handles zany characters in error message, #1705' do
      skip 'skipped! test requires ruby 2.1+' if RUBY_VERSION <= '2.1.0'

      assert_raises RuntimeError do
        handler.local(worker, jobstr, 'default') do
          raise "kerblammo! #{195.chr}"
        end
      end
      assert_equal "kerblammo! �", job["error_message"]
    end

    # In the rare event that an error message raises an error itself,
    # allow the job to retry. This will likely only happen for custom
    # error classes that override #message
    it 'handles error message that raises an error' do
      assert_raises RuntimeError do
        handler.local(worker, jobstr, 'default') do
          raise BadErrorMessage.new
        end
      end

      assert_equal 1, Sidekiq::RetrySet.new.size
      refute_nil job["error_message"]
    end

    it 'allows a max_retries option in initializer' do
      max_retries = 7
      1.upto(max_retries + 1) do |i|
        assert_raises RuntimeError do
          job = i > 1 ? jobstr('retry_count' => i - 2) : jobstr
          handler(:max_retries => max_retries).local(worker, job, 'default') do
            raise "kerblammo!"
          end
        end
      end

      assert_equal max_retries, Sidekiq::RetrySet.new.size
      assert_equal 1, Sidekiq::DeadSet.new.size
    end

    it 'saves backtraces' do
      c = nil
      assert_raises RuntimeError do
        handler.local(worker, jobstr('backtrace' => true), 'default') do
          c = caller(0); raise "kerblammo!"
        end
      end

      job = Sidekiq::RetrySet.new.first
      assert job.error_backtrace
      assert_equal c[0], job.error_backtrace[0]
    end

    it 'saves partial backtraces' do
      c = nil
      assert_raises RuntimeError do
        handler.local(worker, jobstr('backtrace' => 3), 'default') do
          c = caller(0)[0...3]; raise "kerblammo!"
        end
      end

      job = Sidekiq::RetrySet.new.first
      assert job.error_backtrace
      assert_equal c, job.error_backtrace
      assert_equal 3, c.size
    end

    it 'handles a new failed message' do
      assert_raises RuntimeError do
        handler.local(worker, jobstr, 'default') do
          raise "kerblammo!"
        end
      end
      assert_equal 'default', job["queue"]
      assert_equal 'kerblammo!', job["error_message"]
      assert_equal 'RuntimeError', job["error_class"]
      assert_equal 0, job["retry_count"]
      refute job["error_backtrace"]
      assert job["failed_at"]
    end

    it 'shuts down without retrying work-in-progress, which will resume' do
      rs = Sidekiq::RetrySet.new
      assert_equal 0, rs.size
      msg = { 'class' => 'Bob', 'args' => [1,2,'foo'], 'retry' => true }
      assert_raises Sidekiq::Shutdown do
        handler.local(worker, msg, 'default') do
          raise Sidekiq::Shutdown
        end
      end
      assert_equal 0, rs.size
    end

    it 'shuts down cleanly when shutdown causes exception' do
      skip('Not supported in Ruby < 2.1.0') if RUBY_VERSION < '2.1.0'

      rs = Sidekiq::RetrySet.new
      assert_equal 0, rs.size
      msg = { 'class' => 'Bob', 'args' => [1,2,'foo'], 'retry' => true }
      assert_raises Sidekiq::Shutdown do
        handler.local(worker, msg, 'default') do
          begin
            raise Sidekiq::Shutdown
          rescue Interrupt
            raise "kerblammo!"
          end
        end
      end
      assert_equal 0, rs.size
    end

    it 'shuts down cleanly when shutdown causes chained exceptions' do
      skip('Not supported in Ruby < 2.1.0') if RUBY_VERSION < '2.1.0'

      rs = Sidekiq::RetrySet.new
      assert_equal 0, rs.size
      assert_raises Sidekiq::Shutdown do
        handler.local(worker, jobstr, 'default') do
          begin
            raise Sidekiq::Shutdown
          rescue Interrupt
            begin
              raise "kerblammo!"
            rescue
              raise "kablooie!"
            end
          end
        end
      end
      assert_equal 0, rs.size
    end

    it 'allows a retry queue' do
      assert_raises RuntimeError do
        handler.local(worker, jobstr("retry_queue" => 'retryx'), 'default') do
          raise "kerblammo!"
        end
      end
      assert_equal 'retryx', job["queue"]
      assert_equal 'kerblammo!', job["error_message"]
      assert_equal 'RuntimeError', job["error_class"]
      assert_equal 0, job["retry_count"]
      refute job["error_backtrace"]
      assert job["failed_at"]
    end

    it 'handles a recurring failed message' do
      now = Time.now.to_f
      msg = {"queue"=>"default", "error_message"=>"kerblammo!", "error_class"=>"RuntimeError", "failed_at"=>now, "retry_count"=>10}
      assert_raises RuntimeError do
        handler.local(worker, jobstr(msg), 'default') do
          raise "kerblammo!"
        end
      end
      assert_equal 'default', job["queue"]
      assert_equal 'kerblammo!', job["error_message"]
      assert_equal 'RuntimeError', job["error_class"]
      assert_equal 11, job["retry_count"]
      assert job["failed_at"]
    end

    it 'throws away old messages after too many retries (using the default)' do
      q = Sidekiq::Queue.new
      rs = Sidekiq::RetrySet.new
      ds = Sidekiq::DeadSet.new
      assert_equal 0, q.size
      assert_equal 0, rs.size
      assert_equal 0, ds.size
      now = Time.now.to_f
      msg = {"queue"=>"default", "error_message"=>"kerblammo!", "error_class"=>"RuntimeError", "failed_at"=>now, "retry_count"=>25}
      assert_raises RuntimeError do
        handler.local(worker, jobstr(msg), 'default') do
          raise "kerblammo!"
        end
      end
      assert_equal 0, q.size
      assert_equal 0, rs.size
      assert_equal 1, ds.size
    end

    describe "custom retry delay" do
      before do
        @old_logger    = Sidekiq.logger
        @tmp_log_path  = '/tmp/sidekiq-retries.log'
        Sidekiq.logger = Logger.new(@tmp_log_path)
      end

      after do
        Sidekiq.logger = @old_logger
        File.unlink @tmp_log_path if File.exist?(@tmp_log_path)
      end

      class CustomWorkerWithoutException
        include Sidekiq::Worker

        sidekiq_retry_in do |count|
          count * 2
        end
      end

      class SpecialError < StandardError
      end

      class CustomWorkerWithException
        include Sidekiq::Worker

        sidekiq_retry_in do |count, exception|
          case exception
          when SpecialError
            Sidekiq::JobRetry::USE_DEFAULT_RETRY_FORMULA
          when ArgumentError
            count * 4
          when ZeroDivisionError
            (count..count * 2)
          else
            count * 2
          end
        end
      end

      class ErrorWorker
        include Sidekiq::Worker

        sidekiq_retry_in do |count|
          count / 0
        end
      end

      it "retries with a default delay" do
        refute_equal 4, handler.__send__(:delay_for, worker, 2, StandardError.new)
      end

      it "retries with a custom delay and exception 1" do
        assert_equal 8, handler.__send__(:delay_for, CustomWorkerWithException, 2, ArgumentError.new)
      end

      it "retries with a custom delay and exception 2" do
        assert_equal 4, handler.__send__(:delay_for, CustomWorkerWithException, 2, StandardError.new)
      end

      it "retries with a custom delay and exception 3" do
        assert_includes 2..4, handler.__send__(:delay_for, CustomWorkerWithException, 2, ZeroDivisionError.new)
      end

      it "retries with a default delay and exception in case of configured with nil" do
        refute_equal 8, handler.__send__(:delay_for, CustomWorkerWithException, 2, SpecialError.new)
        refute_equal 4, handler.__send__(:delay_for, CustomWorkerWithException, 2, SpecialError.new)
      end

      it "retries with a custom delay without exception" do
        assert_equal 4, handler.__send__(:delay_for, CustomWorkerWithoutException, 2, StandardError.new)
      end

      it "falls back to the default retry on exception" do
        refute_equal 4, handler.__send__(:delay_for, ErrorWorker, 2, StandardError.new)
        assert_match(/Failure scheduling retry using the defined `sidekiq_retry_in`/,
                     File.read(@tmp_log_path), 'Log entry missing for sidekiq_retry_in')
      end
    end

    describe 'handles errors withouth cause' do
      before do
        @error = nil
        begin
          raise ::StandardError, 'Error'
        rescue ::StandardError => e
          @error = e
        end
      end

      it "does not recurse infinitely checking if it's a shutdown" do
        assert(!Sidekiq::JobRetry.new.send(
          :exception_caused_by_shutdown?, @error))
      end
    end

    describe 'handles errors with circular causes' do
      before do
        @error = nil
        begin
          begin
            raise ::StandardError, 'Error 1'
          rescue ::StandardError => e1
            begin
              raise ::StandardError, 'Error 2'
            rescue ::StandardError
              raise e1
            end
          end
        rescue ::StandardError => e
          @error = e
        end
      end

      it "does not recurse infinitely checking if it's a shutdown" do
        assert(!Sidekiq::JobRetry.new.send(
          :exception_caused_by_shutdown?, @error))
      end
    end
  end

end
