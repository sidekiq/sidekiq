# frozen_string_literal: true

require_relative "helper"
require "sidekiq/cli"
require "sidekiq/fetch"
require "sidekiq/scheduled"
require "sidekiq/processor"

class JoeWorker
  include Sidekiq::Worker
  def perform(slp)
    raise "boom" if slp == "boom"
    sleep(slp) if slp > 0
    $count += 1
  end
end

describe "Actors" do
  before do
    Sidekiq.redis { |c| c.flushdb }
    @config = Sidekiq
    @config[:fetch] = Sidekiq::BasicFetch.new(@config)
    @config[:error_handlers] << Sidekiq.method(:default_error_handler)
    @config[:queues] = ["default"]
  end

  describe "scheduler" do
    it "can start and stop" do
      f = Sidekiq::Scheduled::Poller.new(@config)
      f.start
      f.terminate
    end

    it "can schedule" do
      ss = Sidekiq::ScheduledSet.new
      q = Sidekiq::Queue.new

      JoeWorker.perform_in(0.01, 0)

      assert_equal 0, q.size
      assert_equal 1, ss.size

      sleep 0.015
      s = Sidekiq::Scheduled::Poller.new(@config)
      s.enqueue
      assert_equal 1, q.size
      assert_equal 0, ss.size
      s.terminate
    end
  end

  describe "processor" do
    before do
      $count = 0
    end

    it "can start and stop" do
      m = Mgr.new
      f = Sidekiq::Processor.new(m, @config)
      f.terminate
    end

    class Mgr
      attr_reader :latest_error
      attr_reader :mutex
      attr_reader :cond
      def initialize
        @mutex = ::Mutex.new
        @cond = ::ConditionVariable.new
      end

      def processor_died(inst, err)
        @latest_error = err
        @mutex.synchronize do
          @cond.signal
        end
      end

      def processor_stopped(inst)
        @mutex.synchronize do
          @cond.signal
        end
      end
    end

    it "can process" do
      mgr = Mgr.new

      q = Sidekiq::Queue.new
      assert_equal 0, q.size
      p = Sidekiq::Processor.new(mgr, @config)
      JoeWorker.perform_async(0)
      assert_equal 1, q.size

      a = $count
      p.process_one
      b = $count
      assert_equal a + 1, b
      assert_equal 0, q.size
    end

    it "deals with errors" do
      mgr = Mgr.new

      p = Sidekiq::Processor.new(mgr, @config)
      JoeWorker.perform_async("boom")
      q = Sidekiq::Queue.new
      assert_equal 1, q.size

      a = $count
      mgr.mutex.synchronize do
        p.start
        mgr.cond.wait(mgr.mutex)
      end
      b = $count
      assert_equal a, b

      sleep 0.001
      assert_equal false, p.thread.status
      p.terminate(true)
      refute_nil mgr.latest_error
      assert_equal RuntimeError, mgr.latest_error.class
    end

    it "gracefully kills" do
      mgr = Mgr.new

      p = Sidekiq::Processor.new(mgr, @config)
      JoeWorker.perform_async(1)
      q = Sidekiq::Queue.new
      assert_equal 1, q.size

      a = $count
      p.start
      sleep(0.05)
      p.terminate
      p.kill(true)

      b = $count
      assert_equal a, b
      assert_equal false, p.thread.status
      refute mgr.latest_error, mgr.latest_error.to_s
    end
  end
end
