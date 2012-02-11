require 'helper'
require 'sidekiq/middleware/chain'
require 'sidekiq/middleware/server/unique_jobs'
require 'sidekiq/processor'

class TestMiddleware < MiniTest::Unit::TestCase
  describe 'middleware chain' do

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
      chain.register do
        use CustomMiddleware, 1, []
      end

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
      Sidekiq::Middleware::Server::UniqueJobs.class_eval do
        def call(*args); yield; end
      end

      recorder = []
      msg = { 'class' => CustomWorker.to_s, 'args' => [recorder] }

      Sidekiq::Processor.middleware.register do
        2.times { |i| use CustomMiddleware, i.to_s, recorder }
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

      chain.register do
        use NonYieldingMiddleware
        use CustomMiddleware, 1, recorder
      end

      final_action = nil
      chain.invoke { final_action = true }
      assert_equal nil, final_action
      assert_equal [], recorder
    end
  end
end
