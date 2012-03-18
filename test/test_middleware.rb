require 'helper'
require 'sidekiq/middleware/chain'
require 'sidekiq/middleware/server/unique_jobs'
require 'sidekiq/processor'

class TestMiddleware < MiniTest::Unit::TestCase
  describe 'middleware chain' do
    before do
      $errors = []
      Sidekiq.redis = REDIS
    end

    it 'handles errors' do
      handler = Sidekiq::Middleware::Server::ExceptionHandler.new

      assert_raises ArgumentError do
        handler.call('', { :a => 1 }, 'default') do
          raise ArgumentError
        end
      end
      assert_equal 1, $errors.size
      assert_equal({ :a => 1 }, $errors[0][:parameters])
    end

    class CustomMiddleware
      def initialize(name, recorder)
        @name = name
        @recorder = recorder
      end

      def call(*args)
        @recorder << [@name, 'before']
        yield
        @recorder << [@name, 'after']
      end
    end

    it 'supports custom middleware' do
      chain = Sidekiq::Middleware::Chain.new
      chain.add CustomMiddleware, 1, []

      assert_equal CustomMiddleware, chain.entries.last.klass
    end

    class CustomWorker
      include Sidekiq::Worker
      def perform(recorder)
        recorder << ['work_performed']
      end
    end

    class NonYieldingMiddleware
      def call(*args)
      end
    end

    it 'executes middleware in the proper order' do
      recorder = []
      msg = { 'class' => CustomWorker.to_s, 'args' => [recorder] }

      Sidekiq.server_middleware do |chain|
        # should only add once, second should be ignored
        2.times { |i| chain.add CustomMiddleware, i.to_s, recorder }
      end

      boss = MiniTest::Mock.new
      processor = Sidekiq::Processor.new(boss)
      boss.expect(:processor_done!, nil, [processor])
      processor.process(msg, 'default')
      assert_equal %w(0 before work_performed 0 after), recorder.flatten
    end

    it 'allows middleware to abruptly stop processing rest of chain' do
      recorder = []
      chain = Sidekiq::Middleware::Chain.new
      chain.add NonYieldingMiddleware
      chain.add CustomMiddleware, 1, recorder

      final_action = nil
      chain.invoke { final_action = true }
      assert_equal nil, final_action
      assert_equal [], recorder
    end
  end
end

class FakeAirbrake
  def self.notify(ex, hash)
    $errors << hash
  end
end
Airbrake = FakeAirbrake
