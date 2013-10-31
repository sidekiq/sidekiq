# encoding: utf-8
require 'helper'

class TestSidekiq < Sidekiq::Test
  describe 'json processing' do
    it 'loads json' do
      assert_equal ({"foo" => "bar"}), Sidekiq.load_json("{\"foo\":\"bar\"}")
    end

    it 'dumps json' do
      assert_equal "{\"foo\":\"bar\"}", Sidekiq.dump_json({ "foo" => "bar" })
    end
  end

  describe "redis connection" do
  	it "returns error without creating a connection if block is not given" do
      mock = Minitest::Mock.new
      mock.expect :create, nil #Sidekiq::RedisConnection, create
  		assert_raises(ArgumentError) {
  			Sidekiq.redis
  		}
      assert_raises(MockExpectationError, "create should not be called") do
        mock.verify
      end
  	end
  end
end
