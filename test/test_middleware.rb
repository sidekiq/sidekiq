require 'helper'
require 'sidekiq/middleware/chain'
require 'sidekiq/processor'

class TestMiddleware < MiniTest::Unit::TestCase
  describe 'middleware chain' do
    before do
      $errors = []
      Sidekiq.redis = REDIS
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
      $recorder = []
      include Sidekiq::Worker
      def perform(recorder)
        $recorder << ['work_performed']
      end
    end

    class NonYieldingMiddleware
      def call(*args)
      end
    end

    class AnotherCustomMiddleware
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

    class YetAnotherCustomMiddleware
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

    it 'executes middleware in the proper order' do
      msg = Sidekiq.dump_json({ 'class' => CustomWorker.to_s, 'args' => [$recorder] })

      Sidekiq.server_middleware do |chain|
        # should only add once, second should be ignored
        2.times { |i| chain.add CustomMiddleware, i.to_s, $recorder }
        chain.insert_before CustomMiddleware, AnotherCustomMiddleware, '2', $recorder
        chain.insert_after AnotherCustomMiddleware, YetAnotherCustomMiddleware, '3', $recorder
      end

      boss = MiniTest::Mock.new
      processor = Sidekiq::Processor.new(boss)
      actor = MiniTest::Mock.new
      actor.expect(:processor_done, nil, [processor])
      boss.expect(:async, actor, [])
      processor.process(Sidekiq::BasicFetch::UnitOfWork.new('queue:default', msg))
      assert_equal %w(2 before 3 before 0 before work_performed 0 after 3 after 2 after), $recorder.flatten
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

  describe 'i18n' do
    before do
      require 'i18n'
      require 'sidekiq/middleware/i18n'
    end

    it 'saves and restores locale' do
      I18n.locale = 'fr'
      msg = {}
      mw = Sidekiq::Middleware::I18n::Client.new
      mw.call(nil, msg, nil) { }
      assert_equal :fr, msg['locale']

      msg['locale'] = 'jp'
      I18n.locale = nil
      assert_equal :en, I18n.locale
      mw = Sidekiq::Middleware::I18n::Server.new
      mw.call(nil, msg, nil) do
        assert_equal :jp, I18n.locale
      end
      assert_equal :en, I18n.locale
    end
  end
end
