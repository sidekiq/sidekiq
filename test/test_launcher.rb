require_relative 'helper'
require 'sidekiq/launcher'

class TestLauncher < Sidekiq::Test

  describe 'launcher' do
    before do
      Sidekiq.redis {|c| c.flushdb }
    end

    def new_manager(opts)
      Sidekiq::Manager.new(opts)
    end

    describe 'heartbeat' do
      before do
        uow = Object.new

        @mgr = new_manager(options)
        @launcher = Sidekiq::Launcher.new(options)
        @launcher.manager = @mgr

        Sidekiq::Processor::WORKER_STATE['a'] = {'b' => 1}

        @proctitle = $0
      end

      after do
        Sidekiq::Processor::WORKER_STATE.clear
        $0 = @proctitle
      end

      describe 'when manager is active' do
        before do
          Sidekiq::CLI::PROCTITLES << proc { "xyz" }
          @launcher.heartbeat('identity', heartbeat_data, Sidekiq.dump_json(heartbeat_data))
          Sidekiq::CLI::PROCTITLES.pop
        end

        it 'sets useful info to proctitle' do
          assert_equal "sidekiq #{Sidekiq::VERSION} myapp [1 of 3 busy] xyz", $0
        end

        it 'stores process info in redis' do
          info = Sidekiq.redis { |c| c.hmget('identity', 'busy') }
          assert_equal ["1"], info
          expires = Sidekiq.redis { |c| c.pttl('identity') }
          assert_in_delta 60000, expires, 500
        end
      end

      describe 'when manager is stopped' do
        before do
          @launcher.quiet
          @launcher.heartbeat('identity', heartbeat_data, Sidekiq.dump_json(heartbeat_data))
        end

        it 'indicates stopping status in proctitle' do
          assert_equal "sidekiq #{Sidekiq::VERSION} myapp [1 of 3 busy] stopping", $0
        end

        it 'stores process info in redis' do
          info = Sidekiq.redis { |c| c.hmget('identity', 'busy') }
          assert_equal ["1"], info
          expires = Sidekiq.redis { |c| c.pttl('identity') }
          assert_in_delta 60000, expires, 50
        end
      end
    end

    def options
      { :concurrency => 3, :queues => ['default'] }
    end

    def heartbeat_data
      { 'concurrency' => 3, 'tag' => 'myapp' }
    end
  end

end
