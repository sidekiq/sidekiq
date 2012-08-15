require 'helper'
require 'sidekiq/cli'
require 'tempfile'

cli = Sidekiq::CLI.instance
def cli.die(code)
  @code = code
end

def cli.valid?
  !@code
end

class TestCli < MiniTest::Unit::TestCase
  describe 'with cli' do

    before do
      @cli = Sidekiq::CLI.instance
    end

    it 'blows up with an invalid require' do
      assert_raises ArgumentError do
        @cli.parse(['sidekiq', '-r', 'foobar'])
      end
    end

    it 'requires the specified Ruby code' do
      @cli.parse(['sidekiq', '-r', './test/fake_env.rb'])
      assert($LOADED_FEATURES.any? { |x| x =~ /fake_env/ })
      assert @cli.valid?
    end

    it 'changes concurrency' do
      @cli.parse(['sidekiq', '-c', '60', '-r', './test/fake_env.rb'])
      assert_equal 60, Sidekiq.options[:concurrency]
    end

    it 'changes queues' do
      @cli.parse(['sidekiq', '-q', 'foo', '-r', './test/fake_env.rb'])
      assert_equal ['foo'], Sidekiq.options[:queues]
    end

    it 'sets strictly ordered queues if weights are not present' do
      @cli.parse(['sidekiq', '-q', 'foo,bar', '-r', './test/fake_env.rb'])
      assert_equal true, !!Sidekiq.options[:strict]
    end

    it 'does not set strictly ordered queues if weights are present' do
      @cli.parse(['sidekiq', '-q', 'foo,3', '-r', './test/fake_env.rb'])
      assert_equal false, !!Sidekiq.options[:strict]
    end

    it 'changes timeout' do
      @cli.parse(['sidekiq', '-t', '30', '-r', './test/fake_env.rb'])
      assert_equal 30, Sidekiq.options[:timeout]
    end

    it 'handles multiple queues with weights with multiple switches' do
      @cli.parse(['sidekiq', '-q', 'foo,3', '-q', 'bar', '-r', './test/fake_env.rb'])
      assert_equal %w(foo foo foo bar), Sidekiq.options[:queues]
    end

    it 'handles multiple queues with weights with a single switch' do
      @cli.parse(['sidekiq', '-q', 'bar,foo,3', '-r', './test/fake_env.rb'])
      assert_equal %w(bar foo foo foo), Sidekiq.options[:queues]
    end

    it 'handles queues with multi-word names' do
      @cli.parse(['sidekiq', '-q', 'queue_one,queue-two', '-r', './test/fake_env.rb'])
      assert_equal %w(queue_one queue-two), Sidekiq.options[:queues]
    end

    it 'sets verbose' do
      old = Sidekiq.logger.level
      @cli.parse(['sidekiq', '-v', '-r', './test/fake_env.rb'])
      assert_equal Logger::DEBUG, Sidekiq.logger.level
      # If we leave the logger at DEBUG it'll add a lot of noise to the test output
      Sidekiq.logger.level = old
    end

    describe 'with pidfile' do
      before do
        @tmp_file = Tempfile.new('sidekiq-test')
        @tmp_path = @tmp_file.path
        @tmp_file.close!

        @cli.parse(['sidekiq', '-P', @tmp_path, '-r', './test/fake_env.rb'])
      end

      after do
        File.unlink @tmp_path if File.exist? @tmp_path
      end

      it 'sets pidfile path' do
        assert_equal @tmp_path, Sidekiq.options[:pidfile]
      end

      it 'writes pidfile' do
        assert_equal File.read(@tmp_path).strip.to_i, Process.pid
      end
    end

    describe 'with config file' do
      before do
        @cli.parse(['sidekiq', '-C', './test/config.yml'])
      end

      it 'takes a path' do
        assert_equal './test/config.yml', Sidekiq.options[:config_file]
      end

      it 'sets verbose' do
        refute Sidekiq.options[:verbose]
      end

      it 'sets require file' do
        assert_equal './test/fake_env.rb', Sidekiq.options[:require]
      end

      it 'sets environment' do
        assert_equal 'xzibit', Sidekiq.options[:environment]
      end

      it 'sets concurrency' do
        assert_equal 50, Sidekiq.options[:concurrency]
      end

      it 'sets pid file' do
        assert_equal '/tmp/sidekiq-config-test.pid', Sidekiq.options[:pidfile]
      end

      it 'sets queues' do
        assert_equal 2, Sidekiq.options[:queues].count { |q| q == 'often' }
        assert_equal 1, Sidekiq.options[:queues].count { |q| q == 'seldom' }
      end
    end

    describe 'with config file and flags' do
      before do
        # We need an actual file here.
        @tmp_lib_path = '/tmp/require-me.rb'
        File.open(@tmp_lib_path, 'w') do |f|
          f.puts "# do work"
        end

        @tmp_file = Tempfile.new('sidekiqr')
        @tmp_path = @tmp_file.path
        @tmp_file.close!

        @cli.parse(['sidekiq',
                    '-C', './test/config.yml',
                    '-e', 'snoop',
                    '-c', '100',
                    '-r', @tmp_lib_path,
                    '-P', @tmp_path,
                    '-q', 'often,7',
                    '-q', 'seldom,3'])
      end

      after do
        File.unlink @tmp_lib_path if File.exist? @tmp_lib_path
        File.unlink @tmp_path if File.exist? @tmp_path
      end

      it 'uses concurrency flag' do
        assert_equal 100, Sidekiq.options[:concurrency]
      end

      it 'uses require file flag' do
        assert_equal @tmp_lib_path, Sidekiq.options[:require]
      end

      it 'uses environment flag' do
        assert_equal 'snoop', Sidekiq.options[:environment]
      end

      it 'uses pidfile flag' do
        assert_equal @tmp_path, Sidekiq.options[:pidfile]
      end

      it 'sets queues' do
        assert_equal 7, Sidekiq.options[:queues].count { |q| q == 'often' }
        assert_equal 3, Sidekiq.options[:queues].count { |q| q == 'seldom' }
      end
    end

    describe 'Sidekiq::CLI#parse_queues' do
      describe 'when weight is present' do
        it 'concatenates queue to opts[:queues] weight number of times' do
          opts = {}
          @cli.send :parse_queues, opts, 'often', 7
          assert_equal %w[often] * 7, opts[:queues]
        end
      end

      describe 'when weight is not present' do
        it 'concatenates queue to opts[:queues] once' do
          opts = {}
          @cli.send :parse_queues, opts, 'once', nil
          assert_equal %w[once], opts[:queues]
        end
      end
    end
  end

end
