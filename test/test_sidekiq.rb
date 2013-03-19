# encoding: utf-8
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

  describe "redis connection" do
  	it "returns error without creating a connection if block is not given" do
      mock = MiniTest::Mock.new
      mock.expect :create, nil #Sidekiq::RedisConnection, create
  		assert_raises(ArgumentError) {
  			Sidekiq.redis
  		}
      assert_raises(MockExpectationError, "create should not be called") do
        mock.verify
      end
  	end
  end

  describe "❨╯°□°❩╯︵┻━┻" do
    before { $stdout = StringIO.new }
    after  { $stdout = STDOUT }

    it "allows angry developers to express their emotional constitution and remedies it" do
      Sidekiq.❨╯°□°❩╯︵┻━┻
      assert_equal "Calm down, bro\n", $stdout.string
    end
  end
end