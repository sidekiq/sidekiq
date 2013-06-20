require 'helper'
require 'sidekiq/util'

class TestUtil < Minitest::Test
  describe 'util' do
    it 'generates the same process id when included in two or more classes' do
      class One
        include Sidekiq::Util
      end

      class Two
        include Sidekiq::Util
      end

      assert_equal One.new.process_id, Two.new.process_id
    end
  end
end
