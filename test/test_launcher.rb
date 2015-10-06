require_relative 'helper'
require 'sidekiq/launcher'

class TestLauncher < Sidekiq::Test

  describe 'launcher' do
    before do
      Sidekiq.redis {|c| c.flushdb }
    end

    def new_manager(opts)
      condvar = Minitest::Mock.new
      condvar.expect(:signal, nil, [])
      Sidekiq::Manager.new(condvar, opts)
    end

    describe 'heartbeat' do
      before do
        uow = Object.new

        @processor = Minitest::Mock.new
        @processor.expect(:request_process, nil, [uow])
        @processor.expect(:hash, 1234, [])

        @mgr = new_manager(options)
        @launcher = Sidekiq::Launcher.new(options)
        @launcher.manager = @mgr

        @mgr.ready << @processor
        @mgr.assign(uow)

        @processor.verify
        @proctitle = $0
      end

      after do
        $0 = @proctitle
      end

      describe 'when manager is active' do
        before do
          Sidekiq::Launcher::PROCTITLES << proc { "xyz" }
          @launcher.heartbeat('identity', heartbeat_data, Sidekiq.dump_json(heartbeat_data))
          Sidekiq::Launcher::PROCTITLES.pop
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
          @processor.expect(:hash, 1234, [])
          @processor.expect(:terminate, [])

          @launcher.quiet
          @launcher.manager.processor_done(@processor)
          @launcher.heartbeat('identity', heartbeat_data, Sidekiq.dump_json(heartbeat_data))

          @processor.verify
        end

        it 'indicates stopping status in proctitle' do
          assert_equal "sidekiq #{Sidekiq::VERSION} myapp [0 of 3 busy] stopping", $0
        end

        it 'stores process info in redis' do
          info = Sidekiq.redis { |c| c.hmget('identity', 'busy') }
          assert_equal ["0"], info
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
