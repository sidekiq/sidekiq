require 'helper'

class TestApi < MiniTest::Unit::TestCase
  describe "stats" do
    before do
      Sidekiq.redis {|c| c.flushdb }
    end

    describe "processed" do
      it "is initially zero" do
        s = Sidekiq::Stats.new
        assert_equal 0, s.processed
      end

      it "returns number of processed jobs" do
        Sidekiq.redis { |conn| conn.set("stat:processed", 5) }
        s = Sidekiq::Stats.new
        assert_equal 5, s.processed
      end
    end

    describe "failed" do
      it "is initially zero" do
        s = Sidekiq::Stats.new
        assert_equal 0, s.processed
      end

      it "returns number of failed jobs" do
        Sidekiq.redis { |conn| conn.set("stat:failed", 5) }
        s = Sidekiq::Stats.new
        assert_equal 5, s.failed
      end
    end

    describe "queues" do
      it "is initially empty" do
        s = Sidekiq::Stats.new
        assert_equal 0, s.queues.size
      end

      it "returns a hash of queue and size in order" do
        Sidekiq.redis do |conn|
          conn.rpush 'queue:foo', '{}'
          conn.sadd 'queues', 'foo'

          3.times { conn.rpush 'queue:bar', '{}' }
          conn.sadd 'queues', 'bar'
        end

        s = Sidekiq::Stats.new
        assert_equal ({ "foo" => 1, "bar" => 3 }), s.queues
        assert_equal "bar", s.queues.first.first
      end
    end

    describe "enqueued" do
      it "is initially empty" do
        s = Sidekiq::Stats.new
        assert_equal 0, s.enqueued
      end

      it "returns total enqueued jobs" do
        Sidekiq.redis do |conn|
          conn.rpush 'queue:foo', '{}'
          conn.sadd 'queues', 'foo'

          3.times { conn.rpush 'queue:bar', '{}' }
          conn.sadd 'queues', 'bar'
        end

        s = Sidekiq::Stats.new
        assert_equal 4, s.enqueued
      end
    end

    describe "over time" do
      describe "processed" do
        it 'retrieves hash of dates' do
          Sidekiq.redis do |c|
            c.incrby("stat:processed:2012-12-24", 4)
            c.incrby("stat:processed:2012-12-25", 1)
            c.incrby("stat:processed:2012-12-26", 6)
            c.incrby("stat:processed:2012-12-27", 2)
          end
          Time.stub(:now, Time.parse("2012-12-26 1:00:00 -0500")) do
            s = Sidekiq::Stats::History.new(2)
            assert_equal ({ "2012-12-26" => 6, "2012-12-25" => 1 }), s.processed

            s = Sidekiq::Stats::History.new(3)
            assert_equal ({ "2012-12-26" => 6, "2012-12-25" => 1, "2012-12-24" => 4 }), s.processed

            s = Sidekiq::Stats::History.new(2, Date.parse("2012-12-25"))
            assert_equal ({ "2012-12-25" => 1, "2012-12-24" => 4 }), s.processed
          end
        end
      end

      describe "failed" do
        it 'retrieves hash of dates' do
          Sidekiq.redis do |c|
            c.incrby("stat:failed:2012-12-24", 4)
            c.incrby("stat:failed:2012-12-25", 1)
            c.incrby("stat:failed:2012-12-26", 6)
            c.incrby("stat:failed:2012-12-27", 2)
          end
          Time.stub(:now, Time.parse("2012-12-26 1:00:00 -0500")) do
            s = Sidekiq::Stats::History.new(2)
            assert_equal ({ "2012-12-26" => 6, "2012-12-25" => 1 }), s.failed

            s = Sidekiq::Stats::History.new(3)
            assert_equal ({ "2012-12-26" => 6, "2012-12-25" => 1, "2012-12-24" => 4 }), s.failed

            s = Sidekiq::Stats::History.new(2, Date.parse("2012-12-25"))
            assert_equal ({ "2012-12-25" => 1, "2012-12-24" => 4 }), s.failed
          end
        end
      end

      describe "cleanup" do
        it 'removes processed stats outside of keep window' do
          Sidekiq.redis do |c|
            c.incrby("stat:processed:2012-05-03", 4)
            c.incrby("stat:processed:2012-06-03", 4)
            c.incrby("stat:processed:2012-07-03", 1)
          end
          Time.stub(:now, Time.parse("2012-12-01 1:00:00 -0500")) do
            Sidekiq::Stats::History.cleanup
            assert_equal false, Sidekiq.redis { |c| c.exists("stat:processed:2012-05-03") }
          end
        end

        it 'removes failed stats outside of keep window' do
          Sidekiq.redis do |c|
            c.incrby("stat:failed:2012-05-03", 4)
            c.incrby("stat:failed:2012-06-03", 4)
            c.incrby("stat:failed:2012-07-03", 1)
          end
          Time.stub(:now, Time.parse("2012-12-01 1:00:00 -0500")) do
            Sidekiq::Stats::History.cleanup
            assert_equal false, Sidekiq.redis { |c| c.exists("stat:failed:2012-05-03") }
          end
        end
      end
    end
  end

  describe 'with an empty database' do
    before do
      Sidekiq.redis {|c| c.flushdb }
    end

    it 'shows queue as empty' do
      q = Sidekiq::Queue.new
      assert_equal 0, q.size
    end

    class ApiWorker
      include Sidekiq::Worker
    end

    it 'can enumerate jobs' do
      q = Sidekiq::Queue.new
      ApiWorker.perform_async(1, 'mike')
      assert_equal ['TestApi::ApiWorker'], q.map(&:klass)

      job = q.first
      assert_equal 24, job.jid.size
      assert_equal [1, 'mike'], job.args

      q = Sidekiq::Queue.new('other')
      assert_equal 0, q.size
    end

    it 'can delete jobs' do
      q = Sidekiq::Queue.new
      ApiWorker.perform_async(1, 'mike')
      assert_equal 1, q.size
      assert_equal [true], q.map(&:delete)
      assert_equal 0, q.size
    end

    it 'can find job by id in sorted sets' do
      q = Sidekiq::Queue.new
      job_id = ApiWorker.perform_in(100, 1, 'jason')
      job = Sidekiq::ScheduledSet.new.find_job(job_id)
      refute_nil job
      assert_equal job_id, job.jid
    end

    it 'can find job by id in queues' do
      q = Sidekiq::Queue.new
      job_id = ApiWorker.perform_async(1, 'jason')
      job = q.find_job(job_id)
      refute_nil job
      assert_equal job_id, job.jid
    end

    it 'can clear a queue' do
      q = Sidekiq::Queue.new
      2.times { ApiWorker.perform_async(1, 'mike') }
      q.clear

      Sidekiq.redis do |conn|
        refute conn.smembers('queues').include?('foo')
        refute conn.exists('queues:foo')
      end
    end

    it 'can fetch by score' do
      same_time = Time.now.to_f
      add_retry('bob1', same_time)
      add_retry('bob2', same_time)
      r = Sidekiq::RetrySet.new
      assert_equal 2, r.fetch(same_time).size
    end

    it 'can fetch by score and jid' do
      same_time = Time.now.to_f
      add_retry('bob1', same_time)
      add_retry('bob2', same_time)
      r = Sidekiq::RetrySet.new
      # jobs = r.fetch(same_time)
      # puts jobs[1].jid
      assert_equal 1, r.fetch(same_time, 'bob1').size
    end

    it 'shows empty retries' do
      r = Sidekiq::RetrySet.new
      assert_equal 0, r.size
    end

    it 'can enumerate retries' do
      add_retry

      r = Sidekiq::RetrySet.new
      assert_equal 1, r.size
      array = r.to_a
      assert_equal 1, array.size

      retri = array.first
      assert_equal 'ApiWorker', retri.klass
      assert_equal 'default', retri.queue
      assert_equal 'bob', retri.jid
      assert_in_delta Time.now.to_f, retri.at.to_f, 0.01
    end

    it 'can delete multiple retries from score' do
      same_time = Time.now.to_f
      add_retry('bob1', same_time)
      add_retry('bob2', same_time)
      r = Sidekiq::RetrySet.new
      assert_equal 2, r.size
      Sidekiq::RetrySet.new.delete(same_time)
      assert_equal 0, r.size
    end

    it 'can delete a single retry from score and jid' do
      same_time = Time.now.to_f
      add_retry('bob1', same_time)
      add_retry('bob2', same_time)
      r = Sidekiq::RetrySet.new
      assert_equal 2, r.size
      Sidekiq::RetrySet.new.delete(same_time, 'bob1')
      assert_equal 1, r.size
    end

    it 'can retry a retry' do
      add_retry
      r = Sidekiq::RetrySet.new
      assert_equal 1, r.size
      r.first.retry
      assert_equal 0, r.size
      assert_equal 1, Sidekiq::Queue.new('default').size
      job = Sidekiq::Queue.new('default').first
      assert_equal 'bob', job.jid
      assert_equal 1, job['retry_count']
    end

    it 'can clear retries' do
      add_retry
      add_retry('test')
      r = Sidekiq::RetrySet.new
      assert_equal 2, r.size
      r.clear
      assert_equal 0, r.size
    end

    it 'can enumerate workers' do
      w = Sidekiq::Workers.new
      assert_equal 0, w.size
      w.each do
        assert false
      end

      s = '12345'
      data = Sidekiq.dump_json({ 'payload' => {}, 'queue' => 'default', 'run_at' => Time.now.to_i })
      Sidekiq.redis do |c|
        c.multi do
          c.sadd('workers', s)
          c.set("worker:#{s}", data)
        end
      end

      assert_equal 1, w.size
      w.each do |x, y|
        assert_equal s, x
        assert_equal 'default', y['queue']
      end
    end

    it 'can reschedule jobs' do
      add_retry('foo1')
      add_retry('foo2')

      retries = Sidekiq::RetrySet.new
      assert_equal 2, retries.size
      refute(retries.map { |r| r.score > (Time.now.to_f + 9) }.any?)

      retries.each do |retri|
        retri.reschedule(Time.now.to_f + 10) if retri.jid == 'foo2'
      end

      assert_equal 2, retries.size
      assert(retries.map { |r| r.score > (Time.now.to_f + 9) }.any?)
    end

    def add_retry(jid = 'bob', at = Time.now.to_f)
      payload = Sidekiq.dump_json('class' => 'ApiWorker', 'args' => [1, 'mike'], 'queue' => 'default', 'jid' => jid, 'retry_count' => 2, 'failed_at' => Time.now.utc)
      Sidekiq.redis do |conn|
        conn.zadd('retry', at.to_s, payload)
      end
    end
  end
end
