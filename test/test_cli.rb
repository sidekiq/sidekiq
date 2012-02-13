require 'helper'
require 'sidekiq/cli'

class TestCli < MiniTest::Unit::TestCase
  describe 'with cli' do
    before do
      @cli = new_cli
    end

    it 'blows up with an invalid require' do
      assert_raises ArgumentError do
        @cli.parse(['sidekiq', '-r', 'foobar'])
      end
    end

    it 'blows up with invalid Ruby' do
      @cli.parse(['sidekiq', '-r', './test/fake_env.rb'])
      assert($LOADED_FEATURES.any? { |x| x =~ /fake_env/ })
      assert @cli.valid?
    end

    it 'changes concurrency' do
      @cli.parse(['sidekiq', '-c', '60', '-r', './test/fake_env.rb'])
      assert_equal 60, @cli.options[:processor_count]
    end

    it 'changes queues' do
      @cli.parse(['sidekiq', '-q', 'foo', '-r', './test/fake_env.rb'])
      assert_equal ['foo'], @cli.options[:queues]
    end

    it 'handles weights' do
      @cli.parse(['sidekiq', '-q', 'foo,3', '-q', 'bar', '-r', './test/fake_env.rb'])
      assert_equal %w(bar foo foo foo), @cli.options[:queues].sort
    end

    def new_cli
      cli = Sidekiq::CLI.new
      def cli.die(code)
        @code = code
      end

      def cli.valid?
        !@code
      end
      cli
    end
  end
end
