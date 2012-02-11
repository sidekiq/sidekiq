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
        require 'sidekiq/testing'
        assert_equal 0, DirectWorker.jobs.size
        assert DirectWorker.perform_async(1, 2)
        assert_equal 1, DirectWorker.jobs.size
      ensure
        # Undo override
        Sidekiq::Worker::ClassMethods.class_eval do
          remove_method :perform_async
          alias_method :perform_async, :perform_async_old
          remove_method :perform_async_old
        end
      end
    end

  end
end
