# encoding: utf-8
require_relative 'helper'

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

  describe "❨╯°□°❩╯︵┻━┻" do
    before { $stdout = StringIO.new }
    after  { $stdout = STDOUT }

    it "allows angry developers to express their emotional constitution and remedies it" do
      Sidekiq.❨╯°□°❩╯︵┻━┻
      assert_equal "Calm down, bro\n", $stdout.string
    end
  end

  describe 'lifecycle events' do
    it 'handles invalid input' do
      Sidekiq.options[:lifecycle_events][:startup].clear

      e = assert_raises ArgumentError do
        Sidekiq.on(:startp)
      end
      assert_match(/Invalid event name/, e.message)
      e = assert_raises ArgumentError do
        Sidekiq.on('startup')
      end
      assert_match(/Symbols only/, e.message)
      Sidekiq.on(:startup) do
        1 + 1
      end

      assert_equal 2, Sidekiq.options[:lifecycle_events][:startup].first.call
    end
  end

  describe 'default_worker_options' do
    before do
      @old_options = Sidekiq.default_worker_options
    end
    after  { Sidekiq.default_worker_options = @old_options }

    it 'stringify keys' do
      Sidekiq.default_worker_options = { queue: 'cat'}
      assert_equal 'cat', Sidekiq.default_worker_options['queue']
    end
  end
end
