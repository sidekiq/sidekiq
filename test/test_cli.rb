require_relative 'helper'
require 'sidekiq/cli'
require 'tempfile'

class Sidekiq::CLI
  def die(code)
    @code = code
  end

  def valid?
    !@code
  end
end

class TestCli < Sidekiq::Test
  describe 'CLI#parse' do

    before do
      @cli = Sidekiq::CLI.new
      @opts = Sidekiq.options.dup
    end

    after do
      Sidekiq.options = @opts
    end

    it 'does not require the specified Ruby code' do
      @cli.parse(['sidekiq', '-r', './test/fake_env.rb'])
      refute($LOADED_FEATURES.any? { |x| x =~ /fake_env/ })
      assert @cli.valid?
    end

    it 'does not boot rails' do
      refute defined?(::Rails::Application)
      @cli.parse(['sidekiq', '-r', './myapp'])
      refute defined?(::Rails::Application)
    end

    it 'changes concurrency' do
      @cli.parse(['sidekiq', '-c', '60', '-r', './test/fake_env.rb'])
      assert_equal 60, Sidekiq.options[:concurrency]
    end

    it 'changes queues' do
      @cli.parse(['sidekiq', '-q', 'foo', '-r', './test/fake_env.rb'])
      assert_equal ['foo'], Sidekiq.options[:queues]
    end

    it 'accepts a process index' do
      @cli.parse(['sidekiq', '-i', '7', '-r', './test/fake_env.rb'])
      assert_equal 7, Sidekiq.options[:index]
    end

    it 'accepts a stringy process index' do
      @cli.parse(['sidekiq', '-i', 'worker.7', '-r', './test/fake_env.rb'])
      assert_equal 7, Sidekiq.options[:index]
    end

    it 'sets strictly ordered queues if weights are not present' do
      @cli.parse(['sidekiq', '-q', 'foo', '-q', 'bar', '-r', './test/fake_env.rb'])
      assert_equal true, !!Sidekiq.options[:strict]
    end

    it 'does not set strictly ordered queues if weights are present' do
      @cli.parse(['sidekiq', '-q', 'foo,3', '-r', './test/fake_env.rb'])
      assert_equal false, !!Sidekiq.options[:strict]
    end

    it 'does not set strictly ordered queues if weights are present with multiple queues' do
      @cli.parse(['sidekiq', '-q', 'foo,3', '-q', 'bar', '-r', './test/fake_env.rb'])
      assert_equal false, !!Sidekiq.options[:strict]
    end

    it 'changes timeout' do
      @cli.parse(['sidekiq', '-t', '30', '-r', './test/fake_env.rb'])
      assert_equal 30, Sidekiq.options[:timeout]
    end

    it 'handles multiple queues with weights' do
      @cli.parse(['sidekiq', '-q', 'foo,3', '-q', 'bar', '-r', './test/fake_env.rb'])
      assert_equal %w(foo foo foo bar), Sidekiq.options[:queues]
    end

    it 'handles queues with multi-word names' do
      @cli.parse(['sidekiq', '-q', 'queue_one', '-q', 'queue-two', '-r', './test/fake_env.rb'])
      assert_equal %w(queue_one queue-two), Sidekiq.options[:queues]
    end

    it 'handles queues with dots in the name' do
      @cli.parse(['sidekiq', '-q', 'foo.bar', '-r', './test/fake_env.rb'])
      assert_equal ['foo.bar'], Sidekiq.options[:queues]
    end

    it 'sets verbose' do
      old = Sidekiq.logger.level
      @cli.parse(['sidekiq', '-v', '-r', './test/fake_env.rb'])
      assert_equal Logger::DEBUG, Sidekiq.logger.level
      # If we leave the logger at DEBUG it'll add a lot of noise to the test output
      Sidekiq.options.delete(:verbose)
      Sidekiq.logger.level = old
    end

    describe 'with logfile' do
      before do
        @old_logger = Sidekiq.logger
        @tmp_log_path = '/tmp/sidekiq.log'
      end

      after do
        Sidekiq.logger = @old_logger
        Sidekiq.options.delete(:logfile)
        File.unlink @tmp_log_path if File.exist?(@tmp_log_path)
      end

      it 'sets the logfile path' do
        @cli.parse(['sidekiq', '-L', @tmp_log_path, '-r', './test/fake_env.rb'])

        assert_equal @tmp_log_path, Sidekiq.options[:logfile]
      end

      it 'creates and writes to a logfile' do
        @cli.parse(['sidekiq', '-L', @tmp_log_path, '-r', './test/fake_env.rb'])

        Sidekiq.logger.info('test message')

        assert_match(/test message/, File.read(@tmp_log_path), "didn't include the log message")
      end

      it 'appends messages to a logfile' do
        File.open(@tmp_log_path, 'w') do |f|
          f.puts 'already existent log message'
        end

        @cli.parse(['sidekiq', '-L', @tmp_log_path, '-r', './test/fake_env.rb'])

        Sidekiq.logger.info('test message')

        log_file_content = File.read(@tmp_log_path)
        assert_match(/already existent/, log_file_content, "didn't include the old message")
        assert_match(/test message/, log_file_content, "didn't include the new message")
      end
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

      it 'parses as expected' do
        assert_equal './test/config.yml', Sidekiq.options[:config_file]
        refute Sidekiq.options[:verbose]
        assert_equal './test/fake_env.rb', Sidekiq.options[:require]
        assert_equal nil, Sidekiq.options[:environment]
        assert_equal 50, Sidekiq.options[:concurrency]
        assert_equal '/tmp/sidekiq-config-test.pid', Sidekiq.options[:pidfile]
        assert_equal '/tmp/sidekiq.log', Sidekiq.options[:logfile]
        assert_equal 2, Sidekiq.options[:queues].count { |q| q == 'very_often' }
        assert_equal 1, Sidekiq.options[:queues].count { |q| q == 'seldom' }
      end
    end

    describe 'with env based config file' do
      before do
        @cli.parse(['sidekiq', '-e', 'staging', '-C', './test/env_based_config.yml'])
      end

      it 'parses as expected' do
        assert_equal './test/env_based_config.yml', Sidekiq.options[:config_file]
        refute Sidekiq.options[:verbose]
        assert_equal './test/fake_env.rb', Sidekiq.options[:require]
        assert_equal 'staging', Sidekiq.options[:environment]
        assert_equal 5, Sidekiq.options[:concurrency]
        assert_equal '/tmp/sidekiq-config-test.pid', Sidekiq.options[:pidfile]
        assert_equal '/tmp/sidekiq.log', Sidekiq.options[:logfile]
        assert_equal 2, Sidekiq.options[:queues].count { |q| q == 'very_often' }
        assert_equal 1, Sidekiq.options[:queues].count { |q| q == 'seldom' }
      end
    end

    describe 'with an empty config file' do
      before do
        @tmp_file = Tempfile.new('sidekiq-test')
        @tmp_path = @tmp_file.path
        @tmp_file.close!
      end

      after do
        File.unlink @tmp_path if File.exist? @tmp_path
      end

      it 'takes a path' do
        @cli.parse(['sidekiq', '-C', @tmp_path])
        assert_equal @tmp_path, Sidekiq.options[:config_file]
      end

      it 'should have an identical options hash, except for config_file' do
        @cli.parse(['sidekiq'])
        old_options = Sidekiq.options.clone

        @cli.parse(['sidekiq', '-C', @tmp_path])
        new_options = Sidekiq.options.clone
        refute_equal old_options, new_options

        new_options.delete(:config_file)
        assert_equal old_options, new_options
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

      it 'gives the expected options' do
        assert_equal 100, Sidekiq.options[:concurrency]
        assert_equal @tmp_lib_path, Sidekiq.options[:require]
        assert_equal 'snoop', Sidekiq.options[:environment]
        assert_equal @tmp_path, Sidekiq.options[:pidfile]
        assert_equal 7, Sidekiq.options[:queues].count { |q| q == 'often' }
        assert_equal 3, Sidekiq.options[:queues].count { |q| q == 'seldom' }
      end
    end

    describe 'Sidekiq::CLI#parse_queues' do
      describe 'when weight is present' do
        it 'concatenates queues by factor of weight and sets strict to false' do
          opts = { strict: true }
          @cli.__send__ :parse_queues, opts, [['often', 7], ['repeatedly', 3]]
          @cli.__send__ :parse_queues, opts, [['once']]
          assert_equal (%w[often] * 7 + %w[repeatedly] * 3 + %w[once]), opts[:queues]
          assert !opts[:strict]
        end
      end

      describe 'when weight is not present' do
        it 'returns queues and sets strict' do
          opts = { strict: true }
          @cli.__send__ :parse_queues, opts, [['once'], ['one_time']]
          @cli.__send__ :parse_queues, opts, [['einmal']]
          assert_equal %w[once one_time einmal], opts[:queues]
          assert opts[:strict]
        end
      end
    end

    describe 'Sidekiq::CLI#parse_queue' do
      describe 'when weight is present' do
        it 'concatenates queue to opts[:queues] weight number of times and sets strict to false' do
          opts = { strict: true }
          @cli.__send__ :parse_queue, opts, 'often', 7
          assert_equal %w[often] * 7, opts[:queues]
          assert !opts[:strict]
        end
      end

      describe 'when weight is not present' do
        it 'concatenates queue to opts[:queues] once and leaves strict true' do
          opts = { strict: true }
          @cli.__send__ :parse_queue, opts, 'once', nil
          assert_equal %w[once], opts[:queues]
          assert opts[:strict]
        end
      end
    end
  end

  describe 'misc' do
    before do
      @cli = Sidekiq::CLI.new
    end

    it 'handles interrupts' do
      assert_raises Interrupt do
        @cli.handle_signal('INT')
      end
      assert_raises Interrupt do
        @cli.handle_signal('TERM')
      end
    end

    describe 'handles USR1 and USR2' do
      before do
        @tmp_log_path = '/tmp/sidekiq.log'
        @cli.parse(['sidekiq', '-L', @tmp_log_path, '-r', './test/fake_env.rb'])
      end

      after do
        File.unlink @tmp_log_path if File.exists? @tmp_log_path
      end

      it 'shuts down the worker' do
        count = 0
        Sidekiq.options[:lifecycle_events][:quiet] = [proc {
          count += 1
        }]
        @cli.launcher = Sidekiq::Launcher.new(Sidekiq.options)
        @cli.handle_signal('USR1')

        assert_equal 1, count
      end

      it 'reopens logs' do
        mock = MiniTest::Mock.new
        # reopen_logs returns number of files reopened so mock that
        mock.expect(:call, 1)

        Sidekiq::Logging.stub(:reopen_logs, mock) do
          @cli.handle_signal('USR2')
        end
        mock.verify
      end
    end

    describe 'handles TTIN' do
      before do
        @tmp_log_path = '/tmp/sidekiq.log'
        @cli.parse(['sidekiq', '-L', @tmp_log_path, '-r', './test/fake_env.rb'])
        @mock_thread = MiniTest::Mock.new
        @mock_thread.expect(:[], 'interrupt_test', ['label'])
      end

      after do
        File.unlink @tmp_log_path if File.exists? @tmp_log_path
      end

      describe 'with backtrace' do
        it 'logs backtrace' do
          2.times { @mock_thread.expect(:backtrace, ['something went wrong']) }

          Thread.stub(:list, [@mock_thread]) do
            @cli.handle_signal('TTIN')
            assert_match(/something went wrong/, File.read(@tmp_log_path), "didn't include the log message")
          end
        end
      end

      describe 'without backtrace' do
        it 'logs no backtrace available' do
          @mock_thread.expect(:backtrace, nil)

          Thread.stub(:list, [@mock_thread]) do
            @cli.handle_signal('TTIN')
            assert_match(/no backtrace available/, File.read(@tmp_log_path), "didn't include the log message")
          end
        end
      end
    end


    it 'can fire events' do
      count = 0
      Sidekiq.options[:lifecycle_events][:startup] = [proc {
        count += 1
      }]
      cli = Sidekiq::CLI.new
      cli.fire_event(:startup)
      assert_equal 1, count
    end
  end

end
