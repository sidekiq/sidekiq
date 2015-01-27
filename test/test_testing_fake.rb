require_relative 'helper'
require 'sidekiq'
require 'active_record'
require 'action_mailer'
require 'sidekiq/rails'
require 'sidekiq/extensions/action_mailer'
require 'sidekiq/extensions/active_record'

Sidekiq.hook_rails!

class TestTesting < Sidekiq::Test
  describe 'sidekiq testing' do
    class PerformError < RuntimeError; end

    class DirectJob
      include Sidekiq::Job
      def perform(a, b)
        a + b
      end
    end

    class EnqueuedJob
      include Sidekiq::Job
      def perform(a, b)
        a + b
      end
    end

    class StoredJob
      include Sidekiq::Job
      def perform(error)
        raise PerformError if error
      end
    end

    class FooMailer < ActionMailer::Base
      def bar(str)
        str
      end
    end

    class FooModel < ActiveRecord::Base
      def bar(str)
        str
      end
    end

    before do
      require 'sidekiq/testing.rb'
      Sidekiq::Testing.fake!
      EnqueuedJob.jobs.clear
      DirectJob.jobs.clear
    end

    after do
      Sidekiq::Testing.disable!
    end

    it 'stubs the async call' do
      assert_equal 0, DirectJob.jobs.size
      assert DirectJob.perform_async(1, 2)
      assert_equal 1, DirectJob.jobs.size
      assert DirectJob.perform_in(10, 1, 2)
      assert_equal 2, DirectJob.jobs.size
      assert DirectJob.perform_at(10, 1, 2)
      assert_equal 3, DirectJob.jobs.size
      assert_in_delta 10.seconds.from_now.to_f, DirectJob.jobs.last['at'], 0.01
    end

    it 'stubs the delay call on mailers' do
      assert_equal 0, Sidekiq::Extensions::DelayedMailer.jobs.size
      FooMailer.delay.bar('hello!')
      assert_equal 1, Sidekiq::Extensions::DelayedMailer.jobs.size
    end

    class Something
      def self.foo(x)
      end
    end

    it 'stubs the delay call on models' do
      assert_equal 0, Sidekiq::Extensions::DelayedClass.jobs.size
      Something.delay.foo(Date.today)
      assert_equal 1, Sidekiq::Extensions::DelayedClass.jobs.size
    end

    it 'stubs the enqueue call' do
      assert_equal 0, EnqueuedJob.jobs.size
      assert Sidekiq::Client.enqueue(EnqueuedJob, 1, 2)
      assert_equal 1, EnqueuedJob.jobs.size
    end

    it 'stubs the enqueue_to call' do
      assert_equal 0, EnqueuedJob.jobs.size
      assert Sidekiq::Client.enqueue_to('someq', EnqueuedJob, 1, 2)
      assert_equal 1, EnqueuedJob.jobs.size
    end

    it 'executes all stored jobs' do
      assert StoredJob.perform_async(false)
      assert StoredJob.perform_async(true)

      assert_equal 2, StoredJob.jobs.size
      assert_raises PerformError do
        StoredJob.drain
      end
      assert_equal 0, StoredJob.jobs.size

    end

    class SpecificJidJob
      include Sidekiq::Job
      class_attribute :count
      self.count = 0
      def perform(worker_jid)
        return unless worker_jid == self.jid
        self.class.count += 1
      end
    end

    it 'execute only jobs with assigned JID' do
      4.times do |i|
        jid = SpecificJidJob.perform_async(nil)
        if i % 2 == 0
          SpecificJidJob.jobs[-1]["args"] = ["wrong_jid"]
        else
          SpecificJidJob.jobs[-1]["args"] = [jid]
        end
      end

      SpecificJidJob.perform_one
      assert_equal 0, SpecificJidJob.count

      SpecificJidJob.perform_one
      assert_equal 1, SpecificJidJob.count

      SpecificJidJob.drain
      assert_equal 2, SpecificJidJob.count
    end

    it 'round trip serializes the job arguments' do
      assert StoredJob.perform_async(:mike)
      job = StoredJob.jobs.first
      assert_equal "mike", job['args'].first
      StoredJob.clear
    end

    it 'perform_one runs only one job' do
      DirectJob.perform_async(1, 2)
      DirectJob.perform_async(3, 4)
      assert_equal 2, DirectJob.jobs.size

      DirectJob.perform_one
      assert_equal 1, DirectJob.jobs.size

      DirectJob.clear
    end

    it 'perform_one raise error upon empty queue' do
      DirectJob.clear
      assert_raises Sidekiq::EmptyQueueError do
        DirectJob.perform_one
      end
    end

    class FirstJob
      include Sidekiq::Job
      class_attribute :count
      self.count = 0
      def perform
        self.class.count += 1
      end
    end

    class SecondJob
      include Sidekiq::Job
      class_attribute :count
      self.count = 0
      def perform
        self.class.count += 1
      end
    end

    class ThirdJob
      include Sidekiq::Job
      class_attribute :count
      def perform
        FirstJob.perform_async
        SecondJob.perform_async
      end
    end

    it 'clears jobs across all workers' do
      Sidekiq::Job.jobs.clear
      FirstJob.count = 0
      SecondJob.count = 0

      assert_equal 0, FirstJob.jobs.size
      assert_equal 0, SecondJob.jobs.size

      FirstJob.perform_async
      SecondJob.perform_async

      assert_equal 1, FirstJob.jobs.size
      assert_equal 1, SecondJob.jobs.size

      Sidekiq::Job.clear_all

      assert_equal 0, FirstJob.jobs.size
      assert_equal 0, SecondJob.jobs.size

      assert_equal 0, FirstJob.count
      assert_equal 0, SecondJob.count
    end

    it 'drains jobs across all workers' do
      Sidekiq::Job.jobs.clear
      FirstJob.count = 0
      SecondJob.count = 0

      assert_equal 0, FirstJob.jobs.size
      assert_equal 0, SecondJob.jobs.size

      assert_equal 0, FirstJob.count
      assert_equal 0, SecondJob.count

      FirstJob.perform_async
      SecondJob.perform_async

      assert_equal 1, FirstJob.jobs.size
      assert_equal 1, SecondJob.jobs.size

      Sidekiq::Job.drain_all

      assert_equal 0, FirstJob.jobs.size
      assert_equal 0, SecondJob.jobs.size

      assert_equal 1, FirstJob.count
      assert_equal 1, SecondJob.count
    end

    it 'drains jobs across all workers even when workers create new jobs' do
      Sidekiq::Job.jobs.clear
      FirstJob.count = 0
      SecondJob.count = 0

      assert_equal 0, ThirdJob.jobs.size

      assert_equal 0, FirstJob.count
      assert_equal 0, SecondJob.count

      ThirdJob.perform_async

      assert_equal 1, ThirdJob.jobs.size

      Sidekiq::Job.drain_all

      assert_equal 0, ThirdJob.jobs.size

      assert_equal 1, FirstJob.count
      assert_equal 1, SecondJob.count
    end

    it 'can execute a job' do
      worker = Minitest::Mock.new
      worker.expect(:perform, nil, [1, 2, 3])
      DirectJob.execute_job(worker, [1, 2, 3])
    end
  end
end
