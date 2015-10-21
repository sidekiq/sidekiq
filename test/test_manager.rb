require_relative 'helper'
require 'sidekiq/manager'

class TestManager < Sidekiq::Test

  describe 'manager' do
    before do
      Sidekiq.redis {|c| c.flushdb }
    end

    def new_manager(opts)
      Sidekiq::Manager.new(opts)
    end

    it 'creates N processor instances' do
      mgr = new_manager(options)
      assert_equal options[:concurrency], mgr.workers.size
    end

    it 'shuts down the system' do
      mgr = new_manager(options)
      mgr.stop(Time.now)
    end

    it 'throws away dead processors' do
      mgr = new_manager(options)
      init_size = mgr.workers.size
      processor = mgr.workers.first
      begin
        mgr.processor_died(processor, 'ignored')

        assert_equal init_size, mgr.workers.size
        refute mgr.workers.include?(processor)
      ensure
        mgr.workers.each {|p| p.terminate(true) }
      end
    end

    it 'does not support invalid concurrency' do
      assert_raises(ArgumentError) { new_manager(concurrency: 0) }
      assert_raises(ArgumentError) { new_manager(concurrency: -1) }
    end

    def options
      { :concurrency => 3, :queues => ['default'] }
    end

  end
end
