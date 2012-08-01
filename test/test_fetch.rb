require 'helper'
require 'sidekiq/fetch'

class TestFetcher < MiniTest::Unit::TestCase
  describe 'Fetcher#queues_cmd' do
    describe 'when queues are strictly ordered' do
      it 'returns the unique ordered queues properly based on priority and order they were passed in' do
        fetcher = Sidekiq::Fetcher.new nil, %w[high medium low default], true
        assert_equal (%w[queue:high queue:medium queue:low queue:default] << 1), fetcher._send_(:queues_cmd)
      end
    end
  end
end
