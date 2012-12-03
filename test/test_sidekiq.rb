require 'helper'

class TestSidekiq < MiniTest::Unit::TestCase
  describe 'json processing' do
    it 'loads json' do
      assert_equal ({"foo" => "bar"}), Sidekiq.load_json("{\"foo\":\"bar\"}")
    end

    it 'dumps json' do
      assert_equal "{\"foo\":\"bar\"}", Sidekiq.dump_json({ "foo" => "bar" })
    end
  end

end