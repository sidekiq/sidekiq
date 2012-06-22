require 'helper'
require 'sidekiq/processor'

class TestProcessor < MiniTest::Unit::TestCase
  describe 'with mock setup' do
    before do
      $invokes = 0
      $errors = []
      @boss = MiniTest::Mock.new
      Celluloid.logger = nil
      Sidekiq.redis = REDIS
    end

    class MockWorker
      include Sidekiq::Worker
      def perform(args)
        raise "kerboom!" if args == 'boom'
        $invokes += 1
      end
    end

    it 'processes as expected' do
      msg = Sidekiq.dump_json({ 'class' => MockWorker.to_s, 'args' => ['myarg'] })
      processor = ::Sidekiq::Processor.new(@boss)
      @boss.expect(:processor_done!, nil, [processor])
      processor.process(msg, 'default')
      @boss.verify
      assert_equal 1, $invokes
      assert_equal 0, $errors.size
    end
  end
end
