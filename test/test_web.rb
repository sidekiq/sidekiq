# encoding: utf-8
# frozen_string_literal: true
require_relative 'helper'
require 'sidekiq/web'
require 'rack/test'
require 'timecop'
require 'mocha/mini_test'

# Tests in this file are a combination of:
#   - Capybara tests (using visit) which render the web ui and check elements.
#       The Capybara tests use Percy.io for visual regression testing.
#   - Rack::Tests (using get & post) for increased speed and simplicity,
#       when we're testing actions rather than UI presentation.

class TestWeb < Sidekiq::Test
  describe 'sidekiq web' do

    include Rack::Test::Methods
    include Capybara::DSL

    def app
      Sidekiq::Web
    end

    def job_params(job, score)
      "#{score}-#{job['jid']}"
    end

    before do
      Sidekiq.redis {|c| c.flushdb }

      Capybara.current_driver = :poltergeist
      Capybara.app = app

      # Freeze time so the time doesn't change in subsequent UI snapshots
      Timecop.freeze(Time.utc(2016, 9, 1, 10, 5, 0))
      # Stub redis_info so memory usage doesn't change in subsequent UI snapshots
      Sidekiq.stubs(:redis_info).returns(Sidekiq::FAKE_INFO)
    end

    after do
      Sidekiq.unstub(:redis_info)
      Timecop.return
      Capybara.use_default_driver
    end

    class WebWorker
      include Sidekiq::Worker

      def perform(a, b)
        a + b
      end
    end

    it 'can configure via set() syntax' do
      app.set(:session_secret, "foo")
      assert_equal "foo", app.session_secret
    end

    it 'can show text with any locales' do
      page.driver.headers = { 'Accept-Language' => 'ru,en' }
      visit '/'
      assert_text('Панель управления')
      snapshot(page, name: 'Dashboard (Russian)')

      page.driver.headers = { 'Accept-Language' => 'es,en' }
      visit '/'
      assert_text('Panel de Control')
      snapshot(page, name: 'Dashboard (Spanish)')

      page.driver.headers = { 'Accept-Language' => 'en-us' }
      visit '/'
      assert_text('Dashboard')
      snapshot(page, name: 'Dashboard (English)')

      page.driver.headers = { 'Accept-Language' => 'zh-cn' }
      visit '/'
      assert_text('信息板')
      snapshot(page, name: 'Dashboard (Chinese)')

      page.driver.headers = { 'Accept-Language' => 'zh-tw' }
      visit '/'
      assert_text('資訊主頁')
      snapshot(page, name: 'Dashboard (Taiwanese)')

      page.driver.headers = { 'Accept-Language' => 'nb' }
      visit '/'
      assert_text('Oversikt')
      snapshot(page, name: 'Dashboard (Norwegian)')

      page.driver.headers = { 'Accept-Language' => 'en-us' }
    end

    describe 'busy' do

      it 'can display workers' do
        Sidekiq.redis do |conn|
          conn.incr('busy')
          conn.sadd('processes', 'foo:1234')
          conn.hmset('foo:1234', 'info', Sidekiq.dump_json('hostname' => 'foo', 'started_at' => Time.now.to_f, "queues" => []), 'at', Time.now.to_f, 'busy', 4)
          identity = 'foo:1234:workers'
          hash = {:queue => 'critical', :payload => { 'class' => WebWorker.name, 'args' => [1,'abc'] }, :run_at => Time.now.to_i }
          conn.hmset(identity, 1001, Sidekiq.dump_json(hash))
        end
        assert_equal ['1001'], Sidekiq::Workers.new.map { |pid, tid, data| tid }

        visit '/busy'
        assert_equal 200, page.status_code
        assert_selector('.status-active')
        assert_text('critical')
        assert_text('WebWorker')

        assert has_button?('Quiet All')
        assert has_button?('Stop All')

        # Check the processes table has 2 rows - the header and process row
        assert_equal 2, page.all('table.processes tr').count
        assert has_button?('Quiet')
        assert has_button?('Stop')

        snapshot(page, name: 'Busy Page')
      end

      it 'can quiet a process' do
        identity = 'identity'
        signals_key = "#{identity}-signals"

        assert_nil Sidekiq.redis { |c| c.lpop signals_key }
        post '/busy', 'quiet' => '1', 'identity' => identity
        assert_equal 302, last_response.status
        assert_equal 'USR1', Sidekiq.redis { |c| c.lpop signals_key }
      end

      it 'can stop a process' do
        identity = 'identity'
        signals_key = "#{identity}-signals"

        assert_nil Sidekiq.redis { |c| c.lpop signals_key }
        post '/busy', 'stop' => '1', 'identity' => identity
        assert_equal 302, last_response.status
        assert_equal 'TERM', Sidekiq.redis { |c| c.lpop signals_key }
      end
    end

    describe 'queues' do
      it 'can display queues' do
        assert Sidekiq::Client.push('queue' => :foo, 'class' => WebWorker, 'args' => [1, 3])

        visit '/queues'
        assert_equal 200, page.status_code
        assert_text('foo')
        assert_no_text('HardWorker')
        snapshot(page, name: 'Queues Page')
      end

      it 'handles queue view' do
        visit '/queues/default'
        assert_equal 200, page.status_code
        snapshot(page, name: 'Queue Page')
      end

      it 'can delete a queue' do
        Sidekiq.redis do |conn|
          conn.rpush('queue:foo', '{}')
          conn.sadd('queues', 'foo')
        end

        get '/queues/foo'
        assert_equal 200, last_response.status

        post '/queues/foo'
        assert_equal 302, last_response.status

        Sidekiq.redis do |conn|
          refute conn.smembers('queues').include?('foo')
          refute conn.exists('queue:foo')
        end
      end

      it 'can delete a job' do
        Sidekiq.redis do |conn|
          conn.rpush('queue:foo', "{}")
          conn.rpush('queue:foo', "{\"foo\":\"bar\"}")
          conn.rpush('queue:foo', "{\"foo2\":\"bar2\"}")
        end

        get '/queues/foo'
        assert_equal 200, last_response.status

        post '/queues/foo/delete', key_val: "{\"foo\":\"bar\"}"
        assert_equal 302, last_response.status

        Sidekiq.redis do |conn|
          refute conn.lrange('queue:foo', 0, -1).include?("{\"foo\":\"bar\"}")
        end
      end
    end


    describe 'retries' do
      it 'can display retries' do
        visit '/retries'
        assert_equal 200, page.status_code
        assert_text('No retries were found')
        assert_no_text('HardWorker')
        snapshot(page, name: 'Retries Page - No Retries')

        add_retry

        visit '/retries'
        assert_equal 200, page.status_code
        assert_no_text('No retries were found')
        assert_text('HardWorker')
        snapshot(page, name: 'Retries Page - With Retry')
      end

      it 'can display a single retry' do
        params = add_retry 'abc'
        visit "/retries/#{job_params(*params)}"
        assert_equal 200, page.status_code
        assert_text('HardWorker')
        assert_text('RuntimeError')
        snapshot(page, name: 'Single Retry Page')
      end

      it 'will redirect to retries when viewing a non-existant retry' do
        get '/retries/0-shouldntexist'
        assert_equal 302, last_response.status
        assert_equal 'http://example.org/retries', last_response.header['Location']
      end

      it 'can delete a single retry' do
        params = add_retry
        post "/retries/#{job_params(*params)}", 'delete' => 'Delete'
        assert_equal 302, last_response.status
        assert_equal 'http://example.org/retries', last_response.header['Location']

        get "/retries"
        assert_equal 200, last_response.status
        refute_match(/#{params.first['args'][2]}/, last_response.body)
      end

      it 'can delete all retries' do
        3.times { add_retry }

        post "/retries/all/delete", 'delete' => 'Delete'
        assert_equal 0, Sidekiq::RetrySet.new.size
        assert_equal 302, last_response.status
        assert_equal 'http://example.org/retries', last_response.header['Location']
      end

      it 'can retry a single retry now' do
        params = add_retry
        post "/retries/#{job_params(*params)}", 'retry' => 'Retry'
        assert_equal 302, last_response.status
        assert_equal 'http://example.org/retries', last_response.header['Location']

        get '/queues/default'
        assert_equal 200, last_response.status
        assert_match(/#{params.first['args'][2]}/, last_response.body)
      end

      it 'can kill a single retry now' do
        params = add_retry
        post "/retries/#{job_params(*params)}", 'kill' => 'Kill'
        assert_equal 302, last_response.status
        assert_equal 'http://example.org/retries', last_response.header['Location']

        get '/morgue'
        assert_equal 200, last_response.status
        assert_match(/#{params.first['args'][2]}/, last_response.body)
      end

      it 'can retry all retries' do
        msg = add_retry.first
        add_retry

        post "/retries/all/retry", 'retry' => 'Retry'
        assert_equal 302, last_response.status
        assert_equal 'http://example.org/retries', last_response.header['Location']
        assert_equal 2, Sidekiq::Queue.new("default").size

        get '/queues/default'
        assert_equal 200, last_response.status
        assert_match(/#{msg['args'][2]}/, last_response.body)
      end
    end

    describe 'scheduled' do
      it 'can display scheduled' do
        visit '/scheduled'
        assert_equal 200, page.status_code
        assert_text('found')
        assert_no_text('HardWorker')
        snapshot(page, name: 'Scheduled Jobs Page - Nothing Scheduled')

        add_scheduled

        visit '/scheduled'
        assert_equal 200, page.status_code
        assert_no_text('found')
        assert_text('HardWorker')
        snapshot(page, name: 'Scheduled Jobs Page - Job Scheduled')
      end

      it 'can display a single scheduled job' do
        params = add_scheduled 'abc'
        visit "/scheduled/#{job_params(*params)}"
        assert_equal 200, page.status_code
        assert_text 'HardWorker'
        snapshot(page, name: 'Scheduled Job Page')
      end

      it 'handles missing scheduled job' do
        get "/scheduled/0-shouldntexist"
        assert_equal 302, last_response.status
        assert_equal 'http://example.org/scheduled', last_response.header['Location']
      end

      it 'can add to queue a single scheduled job' do
        params = add_scheduled
        post "/scheduled/#{job_params(*params)}", 'add_to_queue' => true
        assert_equal 302, last_response.status
        assert_equal 'http://example.org/scheduled', last_response.header['Location']

        get '/queues/default'
        assert_equal 200, last_response.status
        assert_match(/#{params.first['args'][2]}/, last_response.body)
      end

      it 'can delete a single scheduled job' do
        params = add_scheduled
        post "/scheduled/#{job_params(*params)}", 'delete' => 'Delete'
        assert_equal 302, last_response.status
        assert_equal 'http://example.org/scheduled', last_response.header['Location']

        get "/scheduled"
        assert_equal 200, last_response.status
        refute_match(/#{params.first['args'][2]}/, last_response.body)
      end

      it 'can delete scheduled' do
        params = add_scheduled
        Sidekiq.redis do |conn|
          assert_equal 1, conn.zcard('schedule')
          post '/scheduled', 'key' => [job_params(*params)], 'delete' => 'Delete'
          assert_equal 302, last_response.status
          assert_equal 'http://example.org/scheduled', last_response.header['Location']
          assert_equal 0, conn.zcard('schedule')
        end
      end

      it "can move scheduled to default queue" do
        q = Sidekiq::Queue.new
        params = add_scheduled
        Sidekiq.redis do |conn|
          assert_equal 1, conn.zcard('schedule')
          assert_equal 0, q.size
          post '/scheduled', 'key' => [job_params(*params)], 'add_to_queue' => 'AddToQueue'
          assert_equal 302, last_response.status
          assert_equal 'http://example.org/scheduled', last_response.header['Location']
          assert_equal 0, conn.zcard('schedule')
          assert_equal 1, q.size
          get '/queues/default'
          assert_equal 200, last_response.status
          assert_match(/#{params[0]['args'][2]}/, last_response.body)
        end
      end
    end

    it 'calls updatePage() once when polling' do
      get '/busy?poll=true'
      assert_equal 200, last_response.status
      assert_equal 1, last_response.body.scan('data-poll-path="/busy').count
    end

    it 'escape job args and error messages' do
      # on /retries page
      params = add_xss_retry
      get '/retries'
      assert_equal 200, last_response.status
      assert_match(/FailWorker/, last_response.body)

      assert last_response.body.include?( "fail message: &lt;a&gt;hello&lt;&#x2F;a&gt;" )
      assert !last_response.body.include?( "fail message: <a>hello</a>" )

      assert last_response.body.include?( "args\">&quot;&lt;a&gt;hello&lt;&#x2F;a&gt;&quot;<" )
      assert !last_response.body.include?( "args\"><a>hello</a><" )

      # on /workers page
      Sidekiq.redis do |conn|
        pro = 'foo:1234'
        conn.sadd('processes', pro)
        conn.hmset(pro, 'info', Sidekiq.dump_json('started_at' => Time.now.to_f, 'labels' => ['frumduz'], 'queues' =>[]), 'busy', 1, 'beat', Time.now.to_f)
        identity = "#{pro}:workers"
        hash = {:queue => 'critical', :payload => { 'class' => "FailWorker", 'args' => ["<a>hello</a>"] }, :run_at => Time.now.to_i }
        conn.hmset(identity, 100001, Sidekiq.dump_json(hash))
        conn.incr('busy')
      end

      get '/busy'
      assert_equal 200, last_response.status
      assert_match(/FailWorker/, last_response.body)
      assert_match(/frumduz/, last_response.body)
      assert last_response.body.include?( "&lt;a&gt;hello&lt;&#x2F;a&gt;" )
      assert !last_response.body.include?( "<a>hello</a>" )

      # on /queues page
      params = add_xss_retry # sorry, don't know how to easily make this show up on queues page otherwise.
      post "/retries/#{job_params(*params)}", 'retry' => 'Retry'
      assert_equal 302, last_response.status

      get '/queues/foo'
      assert_equal 200, last_response.status
      assert last_response.body.include?( "&lt;a&gt;hello&lt;&#x2F;a&gt;" )
      assert !last_response.body.include?( "<a>hello</a>" )
    end

    it 'can show user defined tab' do
      begin
        Sidekiq::Web.tabs['Custom Tab'] = '/custom'

        get '/'
        assert_match 'Custom Tab', last_response.body

      ensure
        Sidekiq::Web.tabs.delete 'Custom Tab'
      end
    end

    it 'can display home' do
      get '/'
      assert_equal 200, last_response.status
    end

    describe 'custom locales' do
      before do
        Sidekiq::Web.settings.locales << File.join(File.dirname(__FILE__), "fixtures")
        Sidekiq::Web.tabs['Custom Tab'] = '/custom'
        Sidekiq::WebApplication.get('/custom') do
          clear_caches # ugly hack since I can't figure out how to access WebHelpers outside of this context
          t('translated_text')
        end
      end

      after do
        Sidekiq::Web.tabs.delete 'Custom Tab'
        Sidekiq::Web.settings.locales.pop
      end

      it 'can show user defined tab with custom locales' do
        get '/custom'

        assert_match(/Changed text/, last_response.body)
      end
    end

    describe 'dashboard/stats' do
      it 'redirects to stats' do
        get '/dashboard/stats'
        assert_equal 302, last_response.status
        assert_equal 'http://example.org/stats', last_response.header['Location']
      end
    end

    describe 'stats' do
      include Sidekiq::Util

      before do
        Sidekiq.redis do |conn|
          conn.set("stat:processed", 5)
          conn.set("stat:failed", 2)
          conn.sadd("queues", "default")
        end
        2.times { add_retry }
        3.times { add_scheduled }
        4.times { add_worker }
      end

      it 'works' do
        get '/stats'
        @response = Sidekiq.load_json(last_response.body)
        assert_equal 200, last_response.status
        assert_includes @response.keys, "sidekiq"
        assert_equal 5, @response["sidekiq"]["processed"]
        assert_equal 2, @response["sidekiq"]["failed"]
        assert_equal 4, @response["sidekiq"]["busy"]
        assert_equal 1, @response["sidekiq"]["processes"]
        assert_equal 2, @response["sidekiq"]["retries"]
        assert_equal 3, @response["sidekiq"]["scheduled"]
        assert_equal 0, @response["sidekiq"]["default_latency"]
        assert_includes @response.keys, "redis"
        assert_includes @response["redis"].keys, "redis_version"
        assert_includes @response["redis"].keys, "uptime_in_days"
        assert_includes @response["redis"].keys, "connected_clients"
        assert_includes @response["redis"].keys, "used_memory_human"
        assert_includes @response["redis"].keys, "used_memory_peak_human"
      end
    end

    describe 'stats/queues' do
      include Sidekiq::Util

      before do
        Sidekiq.redis do |conn|
          conn.set("stat:processed", 5)
          conn.set("stat:failed", 2)
          conn.sadd("queues", "default")
          conn.sadd("queues", "queue2")
        end
        2.times { add_retry }
        3.times { add_scheduled }
        4.times { add_worker }

        get '/stats/queues'
        @response = Sidekiq.load_json(last_response.body)
      end

      it 'reports the queue depth' do
        assert_equal 0, @response["default"]
        assert_equal 0, @response["queue2"]
      end
    end

    describe 'dead jobs' do
      it 'shows empty index' do
        visit '/morgue'
        assert_equal 200, page.status_code
        snapshot(page, name: 'Dead Jobs Page - Empty')
      end

      it 'shows index with jobs' do
        (_, score) = add_dead
        visit '/morgue'
        assert_equal 200, page.status_code
        assert_text(score.to_i)
        snapshot(page, name: 'Dead Jobs Page - With Job')
      end

      it 'can delete all dead' do
        3.times { add_dead }

        assert_equal 3, Sidekiq::DeadSet.new.size
        post "/morgue/all/delete", 'delete' => 'Delete'
        assert_equal 0, Sidekiq::DeadSet.new.size
        assert_equal 302, last_response.status
        assert_equal 'http://example.org/morgue', last_response.header['Location']
      end

      it 'can display a dead job' do
        params = add_dead
        get "/morgue/#{job_params(*params)}"
        assert_equal 200, last_response.status
        snapshot(page, name: 'Dead Job Page')
      end

      it 'can retry a dead job' do
        params = add_dead
        post "/morgue/#{job_params(*params)}", 'retry' => 'Retry'
        assert_equal 302, last_response.status
        assert_equal 'http://example.org/morgue', last_response.header['Location']

        get '/queues/foo'
        assert_equal 200, last_response.status
        assert_match(/#{params.first['args'][2]}/, last_response.body)
      end

      it 'handles bad query input' do
        get '/queues/foo?page=B<H'
        assert_equal 200, last_response.status
        assert_match(/B%3CH/, last_response.body)
      end
    end

    def add_scheduled(job_id=SecureRandom.hex(12))
      score = Time.now.to_f
      msg = { 'class' => 'HardWorker',
              'args' => ['bob', 1, Time.now.to_f],
              'jid' => job_id }
      Sidekiq.redis do |conn|
        conn.zadd('schedule', score, Sidekiq.dump_json(msg))
      end
      [msg, score]
    end

    def add_retry(job_id=SecureRandom.hex(12))
      msg = { 'class' => 'HardWorker',
              'args' => ['bob', 1, Time.now.to_f],
              'queue' => 'default',
              'error_message' => 'Some fake message',
              'error_class' => 'RuntimeError',
              'retry_count' => 0,
              'failed_at' => Time.now.to_f,
              'jid' => job_id }
      score = Time.now.to_f
      Sidekiq.redis do |conn|
        conn.zadd('retry', score, Sidekiq.dump_json(msg))
      end

      [msg, score]
    end

    def add_dead(job_id=SecureRandom.hex(12))
      msg = { 'class' => 'HardWorker',
              'args' => ['bob', 1, Time.now.to_f],
              'queue' => 'foo',
              'error_message' => 'Some fake message',
              'error_class' => 'RuntimeError',
              'retry_count' => 0,
              'failed_at' => Time.now.utc,
              'jid' => job_id }
      score = Time.now.to_f
      Sidekiq.redis do |conn|
        conn.zadd('dead', score, Sidekiq.dump_json(msg))
      end
      [msg, score]
    end

    def add_xss_retry(job_id=SecureRandom.hex(12))
      msg = { 'class' => 'FailWorker',
              'args' => ['<a>hello</a>'],
              'queue' => 'foo',
              'error_message' => 'fail message: <a>hello</a>',
              'error_class' => 'RuntimeError',
              'retry_count' => 0,
              'failed_at' => Time.now.to_f,
              'jid' => job_id }
      score = Time.now.to_f
      Sidekiq.redis do |conn|
        conn.zadd('retry', score, Sidekiq.dump_json(msg))
      end

      [msg, score]
    end

    def add_worker
      key = "#{hostname}:#{$$}"
      msg = "{\"queue\":\"default\",\"payload\":{\"retry\":true,\"queue\":\"default\",\"timeout\":20,\"backtrace\":5,\"class\":\"HardWorker\",\"args\":[\"bob\",10,5],\"jid\":\"2b5ad2b016f5e063a1c62872\"},\"run_at\":1361208995}"
      Sidekiq.redis do |conn|
        conn.multi do
          conn.sadd("processes", key)
          conn.hmset(key, 'info', Sidekiq.dump_json('hostname' => 'foo', 'started_at' => Time.now.to_f, "queues" => []), 'at', Time.now.to_f, 'busy', 4)
          conn.hmset("#{key}:workers", Time.now.to_f, msg)
        end
      end
    end

    def snapshot(page, options)
      Percy::Capybara.snapshot(page, options) if percy_enabled?
    end
  end
end
