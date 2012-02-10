require 'helper'
require 'sidekiq/worker'

class TestTesting < MiniTest::Unit::TestCase
  describe 'sidekiq testing' do

    class DirectWorker
      include Sidekiq::Worker
      def perform(a, b)
        a + b
      end
    end

    it 'calls the worker directly when in testing mode' do
      begin
        # Override Sidekiq::Worker
        load 'sidekiq/testing.rb'
        assert_equal 3, DirectWorker.perform_async(1, 2)
      ensure
        # Undo override
        load 'sidekiq/worker.rb'
      end
    end

  end
end
