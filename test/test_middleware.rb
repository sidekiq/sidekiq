require 'helper'
require 'sidekiq/middleware'
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

      def call(worker, msg, queue)
        @recorder << [@name, 'before']
        yield
        @recorder << [@name, 'after']
      end
    end

    it 'configures default middleware' do
      chain = Sidekiq::Middleware::Chain.chain
      assert_equal chain, Sidekiq::Middleware::Chain.default
    end

    it 'supports custom middleware' do
      Sidekiq::Middleware::Chain.register do
        use CustomMiddleware, 1, []
      end
      chain = Sidekiq::Middleware::Chain.chain
      assert_equal chain.last.klass, CustomMiddleware
    end

    class CustomWorker
      def perform(recorder)
        recorder << ['work_performed']
      end
    end

    it 'executes middleware in the proper order' do
      Sidekiq::Middleware::EncodedMessageRemover.class_eval do
        def call(worker, msg, queue); yield; end
      end

      recorder = []
      msg = { 'class' => CustomWorker.to_s, 'args' => [recorder] }

      Sidekiq::Middleware::Chain.register do
        2.times { |i| use CustomMiddleware, i.to_s, recorder }
      end

      processor = Sidekiq::Processor.new(@boss)
      @boss.expect(:processor_done!, nil, [processor])
      processor.process(msg, 'default')
      assert_equal recorder.flatten, %w(0 before 1 before work_performed 1 after 0 after)
    end
  end
end




