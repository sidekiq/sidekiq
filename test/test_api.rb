# frozen_string_literal: true

require_relative "helper"
require "sidekiq/api"
require "active_job"
require "action_mailer"

describe "API" do
  before do
    Sidekiq.redis { |c| c.flushdb }
  end

  describe "stats" do
    it "is initially zero" do
      s = Sidekiq::Stats.new
      assert_equal 0, s.processed
      assert_equal 0, s.failed
      assert_equal 0, s.enqueued
      assert_equal 0, s.default_queue_latency
      assert_equal 0, s.workers_size
    end

    describe "processed" do
      it "returns number of processed jobs" do
        Sidekiq.redis { |conn| conn.set("stat:processed", 5) }
        s = Sidekiq::Stats.new
        assert_equal 5, s.processed
      end
    end

    describe "failed" do
      it "returns number of failed jobs" do
        Sidekiq.redis { |conn| conn.set("stat:failed", 5) }
        s = Sidekiq::Stats.new
        assert_equal 5, s.failed
      end
    end

    describe "reset" do
      before do
        Sidekiq.redis do |conn|
          conn.set("stat:processed", 5)
          conn.set("stat:failed", 10)
        end
      end

      it "will reset all stats by default" do
        Sidekiq::Stats.new.reset
        s = Sidekiq::Stats.new
        assert_equal 0, s.failed
        assert_equal 0, s.processed
      end

      it "can reset individual stats" do
        Sidekiq::Stats.new.reset("failed")
        s = Sidekiq::Stats.new
        assert_equal 0, s.failed
        assert_equal 5, s.processed
      end

      it "can accept anything that responds to #to_s" do
        Sidekiq::Stats.new.reset(:failed)
        s = Sidekiq::Stats.new
        assert_equal 0, s.failed
        assert_equal 5, s.processed
      end

      it 'ignores anything other than "failed" or "processed"' do
        Sidekiq::Stats.new.reset((1..10).to_a, ["failed"])
        s = Sidekiq::Stats.new
        assert_equal 0, s.failed
        assert_equal 5, s.processed
      end
    end

    describe "workers_size" do
      it "retrieves the number of busy workers" do
        Sidekiq.redis do |c|
          c.sadd("processes", "process_1")
          c.sadd("processes", "process_2")
          c.hset("process_1", "busy", 1)
          c.hset("process_2", "busy", 2)
        end
        s = Sidekiq::Stats.new
        assert_equal 3, s.workers_size
      end
    end

    describe "queues" do
      it "is initially empty" do
        s = Sidekiq::Stats::Queues.new
        assert_equal 0, s.lengths.size
      end

      it "returns a hash of queue and size in order" do
        Sidekiq.redis do |conn|
          conn.rpush "queue:foo", "{}"
          conn.sadd "queues", "foo"

          3.times { conn.rpush "queue:bar", "{}" }
          conn.sadd "queues", "bar"
        end

        s = Sidekiq::Stats::Queues.new
        assert_equal ({"foo" => 1, "bar" => 3}), s.lengths
        assert_equal "bar", s.lengths.first.first

        assert_equal Sidekiq::Stats.new.queues, Sidekiq::Stats::Queues.new.lengths
      end
    end

    describe "enqueued" do
      it "handles latency for good jobs" do
        Sidekiq.redis do |conn|
          conn.rpush "queue:default", "{\"enqueued_at\": #{Time.now.to_f}}"
          conn.sadd "queues", "default"
        end
        s = Sidekiq::Stats.new
        assert s.default_queue_latency > 0
        q = Sidekiq::Queue.new
        assert q.latency > 0
      end

      it "handles latency for incomplete jobs" do
        Sidekiq.redis do |conn|
          conn.rpush "queue:default", "{}"
          conn.sadd "queues", "default"
        end
        s = Sidekiq::Stats.new
        assert_equal 0, s.default_queue_latency
        q = Sidekiq::Queue.new
        assert_equal 0, q.latency
      end

      it "returns total enqueued jobs" do
        Sidekiq.redis do |conn|
          conn.rpush "queue:foo", "{}"
          conn.sadd "queues", "foo"

          3.times { conn.rpush "queue:bar", "{}" }
          conn.sadd "queues", "bar"
        end

        s = Sidekiq::Stats.new
        assert_equal 4, s.enqueued
      end
    end

    describe "over time" do
      before do
        require "active_support/core_ext/time/conversions"
        @before = Time::DATE_FORMATS[:default]
        Time::DATE_FORMATS[:default] = "%d/%m/%Y %H:%M:%S"
      end

      after do
        Time::DATE_FORMATS[:default] = @before
      end

      describe "history" do
        it "does not allow invalid input" do
          assert_raises(ArgumentError) { Sidekiq::Stats::History.new(-1) }
          assert_raises(ArgumentError) { Sidekiq::Stats::History.new(0) }
          assert_raises(ArgumentError) { Sidekiq::Stats::History.new(2000) }
          assert Sidekiq::Stats::History.new(200)
        end
      end

      describe "processed" do
        it "retrieves hash of dates" do
          Sidekiq.redis do |c|
            c.incrby("stat:processed:2012-12-24", 4)
            c.incrby("stat:processed:2012-12-25", 1)
            c.incrby("stat:processed:2012-12-26", 6)
            c.incrby("stat:processed:2012-12-27", 2)
          end
          Time.stub(:now, Time.parse("2012-12-26 1:00:00 -0500")) do
            s = Sidekiq::Stats::History.new(2)
            assert_equal({"2012-12-26" => 6, "2012-12-25" => 1}, s.processed)

            s = Sidekiq::Stats::History.new(3)
            assert_equal({"2012-12-26" => 6, "2012-12-25" => 1, "2012-12-24" => 4}, s.processed)

            s = Sidekiq::Stats::History.new(2, Date.parse("2012-12-25"))
            assert_equal({"2012-12-25" => 1, "2012-12-24" => 4}, s.processed)
          end
        end
      end

      describe "failed" do
        it "retrieves hash of dates" do
          Sidekiq.redis do |c|
            c.incrby("stat:failed:2012-12-24", 4)
            c.incrby("stat:failed:2012-12-25", 1)
            c.incrby("stat:failed:2012-12-26", 6)
            c.incrby("stat:failed:2012-12-27", 2)
          end
          Time.stub(:now, Time.parse("2012-12-26 1:00:00 -0500")) do
            s = Sidekiq::Stats::History.new(2)
            assert_equal ({"2012-12-26" => 6, "2012-12-25" => 1}), s.failed

            s = Sidekiq::Stats::History.new(3)
            assert_equal ({"2012-12-26" => 6, "2012-12-25" => 1, "2012-12-24" => 4}), s.failed

            s = Sidekiq::Stats::History.new(2, Date.parse("2012-12-25"))
            assert_equal ({"2012-12-25" => 1, "2012-12-24" => 4}), s.failed
          end
        end
      end
    end
  end

  describe "with an empty database" do
    it "shows queue as empty" do
      q = Sidekiq::Queue.new
      assert_equal 0, q.size
      assert_equal 0, q.latency
    end

    before do
      ActiveJob::Base.queue_adapter = :sidekiq
      ActiveJob::Base.logger = nil
    end

    class ApiMailer < ActionMailer::Base
      def test_email(*)
      end
    end

    class ApiJob < ActiveJob::Base
      def perform(*)
      end
    end

    class ApiWorker
      include Sidekiq::Worker
    end

    class WorkerWithTags
      include Sidekiq::Worker
      sidekiq_options tags: ["foo"]
    end

    it "can enumerate jobs" do
      q = Sidekiq::Queue.new
      Time.stub(:now, Time.new(2012, 12, 26)) do
        ApiWorker.perform_async(1, "mike")
        assert_equal [ApiWorker.name], q.map(&:klass)

        job = q.first
        assert_equal 24, job.jid.size
        assert_equal [1, "mike"], job.args
        assert_equal Time.new(2012, 12, 26), job.enqueued_at
      end
      assert q.latency > 10_000_000

      q = Sidekiq::Queue.new("other")
      assert_equal 0, q.size
    end

    it "enumerates jobs in descending score order" do
      # We need to enqueue more than 50 items, which is the page size when retrieving
      # from Redis to ensure everything is sorted: the pages and the items withing them.
      51.times { ApiWorker.perform_in(100, 1, "foo") }

      set = Sidekiq::ScheduledSet.new.to_a

      assert_equal set.sort_by { |job| -job.score }, set
    end

    it "has no enqueued_at time for jobs enqueued in the future" do
      job_id = ApiWorker.perform_in(100, 1, "foo")
      job = Sidekiq::ScheduledSet.new.find_job(job_id)
      assert_nil job.enqueued_at
    end

    it "unwraps delayed jobs" do
      Sidekiq::Extensions.enable_delay!
      Sidekiq::Queue.delay.foo(1, 2, 3)
      q = Sidekiq::Queue.new
      x = q.first
      assert_equal "Sidekiq::Queue.foo", x.display_class
      assert_equal [1, 2, 3], x.display_args
    end

    it "handles previous (raw Array) error_backtrace format" do
      add_retry
      job = Sidekiq::RetrySet.new.first
      assert_equal ["line1", "line2"], job.error_backtrace
    end

    it "handles previous (marshalled Array) error_backtrace format" do
      backtrace = ["line1", "line2"]
      serialized = Marshal.dump(backtrace)
      compressed = Zlib::Deflate.deflate(serialized)
      encoded = Base64.encode64(compressed)

      payload = Sidekiq.dump_json("class" => "ApiWorker", "args" => [1], "queue" => "default", "jid" => "jid", "error_backtrace" => encoded)
      Sidekiq.redis do |conn|
        conn.zadd("retry", Time.now.to_f.to_s, payload)
      end

      job = Sidekiq::RetrySet.new.first
      assert_equal backtrace, job.error_backtrace
    end

    describe "Rails unwrapping" do
      SERIALIZED_JOBS = {
        "5.x" => [
          '{"class":"ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper","wrapped":"ApiJob","queue":"default","args":[{"job_class":"ApiJob","job_id":"f1bde53f-3852-4ae4-a879-c12eacebbbb0","provider_job_id":null,"queue_name":"default","priority":null,"arguments":[1,2,3],"executions":0,"locale":"en"}],"retry":true,"jid":"099eee72911085a511d0e312","created_at":1568305542.339916,"enqueued_at":1568305542.339947}',
          '{"class":"ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper","wrapped":"ActionMailer::DeliveryJob","queue":"mailers","args":[{"job_class":"ActionMailer::DeliveryJob","job_id":"19cc0115-3d1c-4bbe-a51e-bfa1385895d1","provider_job_id":null,"queue_name":"mailers","priority":null,"arguments":["ApiMailer","test_email","deliver_now",1,2,3],"executions":0,"locale":"en"}],"retry":true,"jid":"37436e5504936400e8cf98db","created_at":1568305542.370133,"enqueued_at":1568305542.370241}'
        ],
        "6.x" => [
          '{"class":"ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper","wrapped":"ApiJob","queue":"default","args":[{"job_class":"ApiJob","job_id":"ff2b48d4-bdce-4825-af6b-ef8c11ab651e","provider_job_id":null,"queue_name":"default","priority":null,"arguments":[1,2,3],"executions":0,"exception_executions":{},"locale":"en","timezone":"UTC","enqueued_at":"2019-09-12T16:28:37Z"}],"retry":true,"jid":"ce121bf77b37ae81fe61b6dc","created_at":1568305717.9469702,"enqueued_at":1568305717.947005}',
          '{"class":"ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper","wrapped":"ActionMailer::MailDeliveryJob","queue":"mailers","args":[{"job_class":"ActionMailer::MailDeliveryJob","job_id":"2f967da1-a389-479c-9a4e-5cc059e6d65c","provider_job_id":null,"queue_name":"mailers","priority":null,"arguments":["ApiMailer","test_email","deliver_now",{"args":[1,2,3],"_aj_symbol_keys":["args"]}],"executions":0,"exception_executions":{},"locale":"en","timezone":"UTC","enqueued_at":"2019-09-12T16:28:37Z"}],"retry":true,"jid":"469979df52bb9ef9f48b49e1","created_at":1568305717.9457421,"enqueued_at":1568305717.9457731}'
        ]
      }.each_pair do |ver, jobs|
        it "unwraps ActiveJob #{ver} jobs" do
          # ApiJob.perform_later(1,2,3)
          # puts Sidekiq::Queue.new.first.value
          x = Sidekiq::JobRecord.new(jobs[0], "default")
          assert_equal ApiJob.name, x.display_class
          assert_equal [1, 2, 3], x.display_args
        end

        it "unwraps ActionMailer #{ver} jobs" do
          # ApiMailer.test_email(1,2,3).deliver_later
          # puts Sidekiq::Queue.new("mailers").first.value
          x = Sidekiq::JobRecord.new(jobs[1], "mailers")
          assert_equal "#{ApiMailer.name}#test_email", x.display_class
          assert_equal [1, 2, 3], x.display_args
        end
      end
    end

    it "has no enqueued_at time for jobs enqueued in the future" do
      job_id = ApiWorker.perform_in(100, 1, "foo")
      job = Sidekiq::ScheduledSet.new.find_job(job_id)
      assert_nil job.enqueued_at
    end

    it "returns tags field for jobs" do
      job_id = ApiWorker.perform_async
      assert_equal [], Sidekiq::Queue.new.find_job(job_id).tags

      job_id = WorkerWithTags.perform_async
      assert_equal ["foo"], Sidekiq::Queue.new.find_job(job_id).tags
    end

    it "can delete jobs" do
      q = Sidekiq::Queue.new
      ApiWorker.perform_async(1, "mike")
      assert_equal 1, q.size

      x = q.first
      assert_equal ApiWorker.name, x.display_class
      assert_equal [1, "mike"], x.display_args

      assert_equal [true], q.map(&:delete)
      assert_equal 0, q.size
    end

    it "can move scheduled job to queue" do
      remain_id = ApiWorker.perform_in(100, 1, "jason")
      job_id = ApiWorker.perform_in(100, 1, "jason")
      job = Sidekiq::ScheduledSet.new.find_job(job_id)
      q = Sidekiq::Queue.new
      job.add_to_queue
      queued_job = q.find_job(job_id)
      refute_nil queued_job
      assert_equal queued_job.jid, job_id
      assert_nil Sidekiq::ScheduledSet.new.find_job(job_id)
      refute_nil Sidekiq::ScheduledSet.new.find_job(remain_id)
    end

    it "handles multiple scheduled jobs when moving to queue" do
      jids = Sidekiq::Client.push_bulk("class" => ApiWorker,
        "args" => [[1, "jason"], [2, "jason"]],
        "at" => Time.now.to_f)
      assert_equal 2, jids.size
      (remain_id, job_id) = jids
      job = Sidekiq::ScheduledSet.new.find_job(job_id)
      q = Sidekiq::Queue.new
      job.add_to_queue
      queued_job = q.find_job(job_id)
      refute_nil queued_job
      assert_equal queued_job.jid, job_id
      assert_nil Sidekiq::ScheduledSet.new.find_job(job_id)
      refute_nil Sidekiq::ScheduledSet.new.find_job(remain_id)
    end

    it "can kill a scheduled job" do
      job_id = ApiWorker.perform_in(100, 1, '{"foo":123}')
      job = Sidekiq::ScheduledSet.new.find_job(job_id)
      ds = Sidekiq::DeadSet.new
      assert_equal 0, ds.size
      job.kill
      assert_equal 1, ds.size
    end

    it "can find a scheduled job by jid" do
      10.times do |idx|
        ApiWorker.perform_in(idx, 1)
      end

      job_id = ApiWorker.perform_in(5, 1)
      job = Sidekiq::ScheduledSet.new.find_job(job_id)
      assert_equal job_id, job.jid

      ApiWorker.perform_in(100, 1, "jid" => "jid_in_args")
      assert_nil Sidekiq::ScheduledSet.new.find_job("jid_in_args")
    end

    it "can remove jobs when iterating over a sorted set" do
      # scheduled jobs must be greater than SortedSet#each underlying page size
      51.times do
        ApiWorker.perform_in(100, "aaron")
      end
      set = Sidekiq::ScheduledSet.new
      set.map(&:delete)
      assert_equal set.size, 0
    end

    it "can remove jobs when iterating over a queue" do
      # initial queue size must be greater than Queue#each underlying page size
      51.times do
        ApiWorker.perform_async(1, "aaron")
      end
      q = Sidekiq::Queue.new
      q.map(&:delete)
      assert_equal q.size, 0
    end

    it "can find job by id in queues" do
      q = Sidekiq::Queue.new
      job_id = ApiWorker.perform_async(1, "jason")
      job = q.find_job(job_id)
      refute_nil job
      assert_equal job_id, job.jid
    end

    it "can clear a queue" do
      q = Sidekiq::Queue.new
      2.times { ApiWorker.perform_async(1, "mike") }
      q.clear

      Sidekiq.redis do |conn|
        refute conn.smembers("queues").include?("foo")
        refute conn.exists?("queue:foo")
      end
    end

    it "can fetch by score" do
      same_time = Time.now.to_f
      add_retry("bob1", same_time)
      add_retry("bob2", same_time)
      r = Sidekiq::RetrySet.new
      assert_equal 2, r.fetch(same_time).size
    end

    it "can fetch by score and jid" do
      same_time = Time.now.to_f
      add_retry("bob1", same_time)
      add_retry("bob2", same_time)
      r = Sidekiq::RetrySet.new
      assert_equal 1, r.fetch(same_time, "bob1").size
    end

    it "can fetch by score range" do
      same_time = Time.now.to_f
      add_retry("bob1", same_time)
      add_retry("bob2", same_time + 1)
      add_retry("bob3", same_time + 2)
      r = Sidekiq::RetrySet.new
      range = (same_time..(same_time + 1))
      assert_equal 2, r.fetch(range).size
    end

    it "can fetch by score range and jid" do
      same_time = Time.now.to_f
      add_retry("bob1", same_time)
      add_retry("bob2", same_time + 1)
      add_retry("bob3", same_time + 2)
      r = Sidekiq::RetrySet.new
      range = (same_time..(same_time + 1))
      jobs = r.fetch(range, "bob2")
      assert_equal 1, jobs.size
      assert_equal jobs[0].jid, "bob2"
    end

    it "shows empty retries" do
      r = Sidekiq::RetrySet.new
      assert_equal 0, r.size
    end

    it "can enumerate retries" do
      add_retry

      r = Sidekiq::RetrySet.new
      assert_equal 1, r.size
      array = r.to_a
      assert_equal 1, array.size

      retri = array.first
      assert_equal "ApiWorker", retri.klass
      assert_equal "default", retri.queue
      assert_equal "bob", retri.jid
      assert_in_delta Time.now.to_f, retri.at.to_f, 0.02
    end

    it "requires a jid to delete an entry" do
      start_time = Time.now.to_f
      add_retry("bob2", Time.now.to_f)
      assert_raises(ArgumentError) do
        Sidekiq::RetrySet.new.delete(start_time)
      end
    end

    it "can delete a single retry from score and jid" do
      same_time = Time.now.to_f
      add_retry("bob1", same_time)
      add_retry("bob2", same_time)
      r = Sidekiq::RetrySet.new
      assert_equal 2, r.size
      Sidekiq::RetrySet.new.delete(same_time, "bob1")
      assert_equal 1, r.size
    end

    it "can retry a retry" do
      add_retry
      r = Sidekiq::RetrySet.new
      assert_equal 1, r.size
      r.first.retry
      assert_equal 0, r.size
      assert_equal 1, Sidekiq::Queue.new("default").size
      job = Sidekiq::Queue.new("default").first
      assert_equal "bob", job.jid
      assert_equal 1, job["retry_count"]
    end

    it "can clear retries" do
      add_retry
      add_retry("test")
      r = Sidekiq::RetrySet.new
      assert_equal 2, r.size
      r.clear
      assert_equal 0, r.size
    end

    it "can scan retries" do
      add_retry
      add_retry("test")
      r = Sidekiq::RetrySet.new
      assert_instance_of Enumerator, r.scan("Worker")
      assert_equal 2, r.scan("ApiWorker").to_a.size
      assert_equal 1, r.scan("*test*").to_a.size
    end

    it "can enumerate processes" do
      identity_string = "identity_string"
      odata = {
        "pid" => 123,
        "hostname" => Socket.gethostname,
        "key" => identity_string,
        "identity" => identity_string,
        "started_at" => Time.now.to_f - 15,
        "queues" => ["foo", "bar"]
      }

      time = Time.now.to_f
      Sidekiq.redis do |conn|
        conn.multi do |transaction|
          transaction.sadd("processes", odata["key"])
          transaction.hmset(odata["key"], "info", Sidekiq.dump_json(odata), "busy", 10, "beat", time)
          transaction.sadd("processes", "fake:pid")
        end
      end

      ps = Sidekiq::ProcessSet.new.to_a
      assert_equal 1, ps.size
      data = ps.first
      assert_equal 10, data["busy"]
      assert_equal time, data["beat"]
      assert_equal 123, data["pid"]
      assert_equal ["foo", "bar"], data.queues
      data.quiet!
      data.stop!
      signals_string = "#{odata["key"]}-signals"
      assert_equal "TERM", Sidekiq.redis { |c| c.lpop(signals_string) }
      assert_equal "TSTP", Sidekiq.redis { |c| c.lpop(signals_string) }
    end

    it "can enumerate workers" do
      w = Sidekiq::Workers.new
      assert_equal 0, w.size
      w.each do
        assert false
      end

      hn = Socket.gethostname
      key = "#{hn}:#{$$}"
      pdata = {"pid" => $$, "hostname" => hn, "started_at" => Time.now.to_i}
      Sidekiq.redis do |conn|
        conn.sadd("processes", key)
        conn.hmset(key, "info", Sidekiq.dump_json(pdata), "busy", 0, "beat", Time.now.to_f)
      end

      s = "#{key}:work"
      data = Sidekiq.dump_json({"payload" => "{}", "queue" => "default", "run_at" => Time.now.to_i})
      Sidekiq.redis do |c|
        c.hmset(s, "1234", data)
      end

      w.each do |p, x, y|
        assert_equal key, p
        assert_equal "1234", x
        assert_equal "default", y["queue"]
        assert_equal({}, y["payload"])
        assert_equal Time.now.year, Time.at(y["run_at"]).year
      end

      s = "#{key}:work"
      data = Sidekiq.dump_json({"payload" => {}, "queue" => "default", "run_at" => (Time.now.to_i - 2 * 60 * 60)})
      Sidekiq.redis do |c|
        c.multi do |transaction|
          transaction.hmset(s, "5678", data)
          transaction.hmset("b#{s}", "5678", data)
        end
      end

      assert_equal ["5678", "1234"], w.map { |_, tid, _| tid }
    end

    it "can reschedule jobs" do
      add_retry("foo1")
      add_retry("foo2")

      retries = Sidekiq::RetrySet.new
      assert_equal 2, retries.size
      refute(retries.map { |r| r.score > (Time.now.to_f + 9) }.any?)

      retries.each do |retri|
        retri.reschedule(Time.now + 15) if retri.jid == "foo1"
        retri.reschedule(Time.now.to_f + 10) if retri.jid == "foo2"
      end

      assert_equal 2, retries.size
      assert(retries.map { |r| r.score > (Time.now.to_f + 9) }.any?)
      assert(retries.map { |r| r.score > (Time.now.to_f + 14) }.any?)
    end

    it "prunes processes which have died" do
      data = {"pid" => rand(10_000), "hostname" => "app#{rand(1_000)}", "started_at" => Time.now.to_f}
      key = "#{data["hostname"]}:#{data["pid"]}"
      Sidekiq.redis do |conn|
        conn.sadd("processes", key)
        conn.hmset(key, "info", Sidekiq.dump_json(data), "busy", 0, "beat", Time.now.to_f)
      end

      ps = Sidekiq::ProcessSet.new
      assert_equal 1, ps.size
      assert_equal 1, ps.to_a.size

      Sidekiq.redis do |conn|
        conn.sadd("processes", "bar:987")
        conn.sadd("processes", "bar:986")
        conn.del("process_cleanup")
      end

      ps = Sidekiq::ProcessSet.new
      assert_equal 1, ps.size
      assert_equal 1, ps.to_a.size
    end

    def add_retry(jid = "bob", at = Time.now.to_f)
      payload = Sidekiq.dump_json("class" => "ApiWorker", "args" => [1, "mike"], "queue" => "default", "jid" => jid, "retry_count" => 2, "failed_at" => Time.now.to_f, "error_backtrace" => ["line1", "line2"])
      Sidekiq.redis do |conn|
        conn.zadd("retry", at.to_s, payload)
      end
    end
  end
end
