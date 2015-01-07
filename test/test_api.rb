require_relative 'helper'

class TestApi < Sidekiq::Test

  describe "stats" do
    before do
      Sidekiq.redis = REDIS
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

    describe "reset" do
      before do
        Sidekiq.redis do |conn|
          conn.set('stat:processed', 5)
          conn.set('stat:failed', 10)
        end
      end

      it 'will reset all stats by default' do
        Sidekiq::Stats.new.reset
        Sidekiq.redis do |conn|
          assert_equal '0', conn.get('stat:processed')
          assert_equal '0', conn.get('stat:failed')
        end
      end

      it 'can reset individual stats' do
        Sidekiq::Stats.new.reset('failed')
        Sidekiq.redis do |conn|
          assert_equal '5', conn.get('stat:processed')
          assert_equal '0', conn.get('stat:failed')
        end
      end

      it 'can accept anything that responds to #to_s' do
        Sidekiq::Stats.new.reset(:failed)
        Sidekiq.redis do |conn|
          assert_equal '5', conn.get('stat:processed')
          assert_equal '0', conn.get('stat:failed')
        end
      end

      it 'ignores anything other than "failed" or "processed"' do
        Sidekiq::Stats.new.reset((1..10).to_a, ['failed'])
        Sidekiq.redis do |conn|
          assert_equal '5', conn.get('stat:processed')
          assert_equal '0', conn.get('stat:failed')
        end
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
    end
  end

  describe 'with an empty database' do
    include Sidekiq::Util

    before do
      Sidekiq.redis = REDIS
      Sidekiq.redis {|c| c.flushdb }
    end

    it 'shows queue as empty' do
      q = Sidekiq::Queue.new
      assert_equal 0, q.size
      assert_equal 0, q.latency
    end

    class ApiWorker
      include Sidekiq::Worker
    end

    it 'can enumerate jobs' do
      q = Sidekiq::Queue.new
      Time.stub(:now, Time.new(2012, 12, 26)) do
        ApiWorker.perform_async(1, 'mike')
        assert_equal ['TestApi::ApiWorker'], q.map(&:klass)

        job = q.first
        assert_equal 24, job.jid.size
        assert_equal [1, 'mike'], job.args
        assert_equal Time.new(2012, 12, 26), job.enqueued_at
      end

      assert q.latency > 10_000_000

      q = Sidekiq::Queue.new('other')
      assert_equal 0, q.size
    end

    it 'unwraps delayed jobs' do
      ApiWorker.delay.foo(1,2,3)
      q = Sidekiq::Queue.new
      x = q.first
      assert_equal "TestApi::ApiWorker.foo", x.display_class
      assert_equal [1,2,3], x.display_args
    end

    it 'can delete jobs' do
      q = Sidekiq::Queue.new
      ApiWorker.perform_async(1, 'mike')
      assert_equal 1, q.size

      x = q.first
      assert_equal "TestApi::ApiWorker", x.display_class
      assert_equal [1,'mike'], x.display_args

      assert_equal [true], q.map(&:delete)
      assert_equal 0, q.size
    end

    it "can move scheduled job to queue" do
      remain_id = ApiWorker.perform_in(100, 1, 'jason')
      job_id = ApiWorker.perform_in(100, 1, 'jason')
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
      jids = Sidekiq::Client.push_bulk('class' => ApiWorker,
                                       'args' => [[1, 'jason'], [2, 'jason']],
                                       'at' => Time.now.to_f)
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

    it 'can find job by id in sorted sets' do
      job_id = ApiWorker.perform_in(100, 1, 'jason')
      job = Sidekiq::ScheduledSet.new.find_job(job_id)
      refute_nil job
      assert_equal job_id, job.jid
      assert_in_delta job.latency, 0.0, 0.1
    end

    it 'can remove jobs when iterating over a sorted set' do
      # scheduled jobs must be greater than SortedSet#each underlying page size
      51.times do
        ApiWorker.perform_in(100, 'aaron')
      end
      set = Sidekiq::ScheduledSet.new
      set.map(&:delete)
      assert_equal set.size, 0
    end

    it 'can remove jobs when iterating over a queue' do
      # initial queue size must be greater than Queue#each underlying page size
      51.times do
        ApiWorker.perform_async(1, 'aaron')
      end
      q = Sidekiq::Queue.new
      q.map(&:delete)
      assert_equal q.size, 0
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
        refute conn.exists('queue:foo')
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
      assert_in_delta Time.now.to_f, retri.at.to_f, 0.02
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

    it 'can enumerate processes' do
      identity_string = "identity_string"
      odata = {
        'pid' => 123,
        'hostname' => hostname,
        'key' => identity_string,
        'identity' => identity_string,
        'started_at' => Time.now.to_f - 15,
      }

      time = Time.now.to_f
      Sidekiq.redis do |conn|
        conn.multi do
          conn.sadd('processes', odata['key'])
          conn.hmset(odata['key'], 'info', Sidekiq.dump_json(odata), 'busy', 10, 'beat', time)
          conn.sadd('processes', 'fake:pid')
        end
      end

      ps = Sidekiq::ProcessSet.new.to_a
      assert_equal 1, ps.size
      data = ps.first
      assert_equal 10, data['busy']
      assert_equal time, data['beat']
      assert_equal 123, data['pid']
      data.quiet!
      data.stop!
      signals_string = "#{odata['key']}-signals"
      assert_equal "TERM", Sidekiq.redis{|c| c.lpop(signals_string) }
      assert_equal "USR1", Sidekiq.redis{|c| c.lpop(signals_string) }
    end

    it 'can enumerate workers' do
      w = Sidekiq::Workers.new
      assert_equal 0, w.size
      w.each do
        assert false
      end

      key = "#{hostname}:#{$$}"
      pdata = { 'pid' => $$, 'hostname' => hostname, 'started_at' => Time.now.to_i }
      Sidekiq.redis do |conn|
        conn.sadd('processes', key)
        conn.hmset(key, 'info', Sidekiq.dump_json(pdata), 'busy', 0, 'beat', Time.now.to_f)
      end

      s = "#{key}:workers"
      data = Sidekiq.dump_json({ 'payload' => {}, 'queue' => 'default', 'run_at' => Time.now.to_i })
      Sidekiq.redis do |c|
        c.hmset(s, '1234', data)
      end

      w.each do |p, x, y|
        assert_equal key, p
        assert_equal "1234", x
        assert_equal 'default', y['queue']
        assert_equal Time.now.year, Time.at(y['run_at']).year
      end

      s = "#{key}:workers"
      data = Sidekiq.dump_json({ 'payload' => {}, 'queue' => 'default', 'run_at' => (Time.now.to_i - 2*60*60) })
      Sidekiq.redis do |c|
        c.multi do
          c.hmset(s, '5678', data)
          c.hmset("b#{s}", '5678', data)
        end
      end

      assert_equal ['1234', '5678'], w.map { |_, tid, _| tid }
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

    it 'prunes processes which have died' do
      data = { 'pid' => rand(10_000), 'hostname' => "app#{rand(1_000)}", 'started_at' => Time.now.to_f }
      key = "#{data['hostname']}:#{data['pid']}"
      Sidekiq.redis do |conn|
        conn.sadd('processes', key)
        conn.hmset(key, 'info', Sidekiq.dump_json(data), 'busy', 0, 'beat', Time.now.to_f)
      end

      ps = Sidekiq::ProcessSet.new
      assert_equal 1, ps.size
      assert_equal 1, ps.to_a.size

      Sidekiq.redis do |conn|
        conn.sadd('processes', "bar:987")
        conn.sadd('processes', "bar:986")
      end

      ps = Sidekiq::ProcessSet.new
      assert_equal 1, ps.size
      assert_equal 1, ps.to_a.size
    end

    def add_retry(jid = 'bob', at = Time.now.to_f)
      payload = Sidekiq.dump_json('class' => 'ApiWorker', 'args' => [1, 'mike'], 'queue' => 'default', 'jid' => jid, 'retry_count' => 2, 'failed_at' => Time.now.to_f)
      Sidekiq.redis do |conn|
        conn.zadd('retry', at.to_s, payload)
      end
    end
  end
end
