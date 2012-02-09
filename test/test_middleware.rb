require 'helper'
require 'sidekiq/middleware/chain'
require 'sidekiq/middleware/server/unique_jobs'
require 'sidekiq/processor'

class TestMiddleware < MiniTest::Unit::TestCase
  describe 'middleware chain' do
    before do
      @boss = MiniTest::Mock.new
      Celluloid.logger = nil
    end

    class CustomMiddleware
      def initialize(name, recorder)
        @name = name
        @recorder = recorder
      end

      def call(worker, msg)
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

      assert_equal chain.entries.last.klass, CustomMiddleware
    end

    class CustomWorker
      def perform(recorder)
        recorder << ['work_performed']
      end
    end

    it 'executes middleware in the proper order' do
      Sidekiq::Middleware::Server::UniqueJobs.class_eval do
        def call(worker, msg); yield; end
      end

      recorder = []
      msg = { 'class' => CustomWorker.to_s, 'args' => [recorder] }

      Sidekiq::Processor.middleware.register do
        2.times { |i| use CustomMiddleware, i.to_s, recorder }
      end

      processor = Sidekiq::Processor.new(@boss)
      @boss.expect(:processor_done!, nil, [processor])
      processor.process(msg)
      assert_equal recorder.flatten, %w(0 before 1 before work_performed 1 after 0 after)
    end
  end
end




