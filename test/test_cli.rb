# frozen_string_literal: true

require_relative 'helper'
require 'sidekiq/cli'

class TestCLI < Minitest::Test
  describe '#parse' do
    before do
      Sidekiq.options = Sidekiq::DEFAULTS.dup
      @logger = Sidekiq.logger
      @logdev = StringIO.new
      Sidekiq.logger = Logger.new(@logdev)
      @cli = Sidekiq::CLI.new
    end

    after do
      Sidekiq.logger = @logger
    end

    describe 'options' do
      describe 'require' do
        it 'accepts with -r' do
          @cli.parse(%w[sidekiq -r ./test/fake_env.rb])

          assert_equal './test/fake_env.rb', Sidekiq.options[:require]
        end
      end

      describe 'concurrency' do
        it 'accepts with -c' do
          @cli.parse(%w[sidekiq -c 60 -r ./test/fake_env.rb])

          assert_equal 60, Sidekiq.options[:concurrency]
        end

        describe 'when concurrency is empty and RAILS_MAX_THREADS env var is set' do
          before do
            ENV['RAILS_MAX_THREADS'] = '9'
          end

          after do
            ENV.delete('RAILS_MAX_THREADS')
          end

          it 'sets concurrency from RAILS_MAX_THREADS env var' do
            @cli.parse(%w[sidekiq -r ./test/fake_env.rb])

            assert_equal 9, Sidekiq.options[:concurrency]
          end

          it 'option overrides RAILS_MAX_THREADS env var' do
            @cli.parse(%w[sidekiq -c 60 -r ./test/fake_env.rb])

            assert_equal 60, Sidekiq.options[:concurrency]
          end
        end
      end

      describe 'queues' do
        it 'accepts with -q' do
          @cli.parse(%w[sidekiq -q foo -r ./test/fake_env.rb])

          assert_equal ['foo'], Sidekiq.options[:queues]
        end

        describe 'when weights are not present' do
          it 'accepts queues without weights' do
            @cli.parse(%w[sidekiq -q foo -q bar -r ./test/fake_env.rb])

            assert_equal ['foo', 'bar'], Sidekiq.options[:queues]
          end

          it 'sets strictly ordered queues' do
            @cli.parse(%w[sidekiq -q foo -q bar -r ./test/fake_env.rb])

            assert_equal true, !!Sidekiq.options[:strict]
          end
        end

        describe 'when weights are present' do
          it 'accepts queues with weights' do
            @cli.parse(%w[sidekiq -q foo,3 -q bar -r ./test/fake_env.rb])

            assert_equal ['foo', 'foo', 'foo', 'bar'], Sidekiq.options[:queues]
          end

          it 'does not set strictly ordered queues' do
            @cli.parse(%w[sidekiq -q foo,3 -q bar -r ./test/fake_env.rb])

            assert_equal false, !!Sidekiq.options[:strict]
          end
        end

        it 'accepts queues with multi-word names' do
          @cli.parse(%w[sidekiq -q queue_one -q queue-two -r ./test/fake_env.rb])

          assert_equal ['queue_one', 'queue-two'], Sidekiq.options[:queues]
        end

        it 'accepts queues with dots in the name' do
          @cli.parse(%w[sidekiq -q foo.bar -r ./test/fake_env.rb])

          assert_equal ['foo.bar'], Sidekiq.options[:queues]
        end

        describe 'when duplicate queue names' do
          it 'raises an argument error' do
            assert_raises(ArgumentError) { @cli.parse(%w[sidekiq -q foo -q foo -r ./test/fake_env.rb]) }
            assert_raises(ArgumentError) { @cli.parse(%w[sidekiq -q foo,3 -q foo,1 -r ./test/fake_env.rb]) }
          end
        end

        describe 'when queues are empty' do
          it "sets 'default' queue" do
            @cli.parse(%w[sidekiq -r ./test/fake_env.rb])

            assert_equal ['default'], Sidekiq.options[:queues]
          end
        end
      end

      describe 'timeout' do
        it 'accepts with -t' do
          @cli.parse(%w[sidekiq -t 30 -r ./test/fake_env.rb])

          assert_equal 30, Sidekiq.options[:timeout]
        end
      end

      describe 'verbose' do
        it 'accepts with -v' do
          @cli.parse(%w[sidekiq -v -r ./test/fake_env.rb])

          assert_equal Logger::DEBUG, Sidekiq.logger.level
        end
      end

      describe 'config file' do
        it 'accepts with -C' do
          @cli.parse(%w[sidekiq -C ./test/config.yml])

          assert_equal './test/config.yml', Sidekiq.options[:config_file]
          refute Sidekiq.options[:verbose]
          assert_equal './test/fake_env.rb', Sidekiq.options[:require]
          assert_nil Sidekiq.options[:environment]
          assert_equal 50, Sidekiq.options[:concurrency]
          assert_equal 2, Sidekiq.options[:queues].count { |q| q == 'very_often' }
          assert_equal 1, Sidekiq.options[:queues].count { |q| q == 'seldom' }
        end

        it 'accepts stringy keys' do
          @cli.parse(%w[sidekiq -C ./test/config_string.yml])

          assert_equal './test/config_string.yml', Sidekiq.options[:config_file]
          refute Sidekiq.options[:verbose]
          assert_equal './test/fake_env.rb', Sidekiq.options[:require]
          assert_nil Sidekiq.options[:environment]
          assert_equal 50, Sidekiq.options[:concurrency]
          assert_equal 2, Sidekiq.options[:queues].count { |q| q == 'very_often' }
          assert_equal 1, Sidekiq.options[:queues].count { |q| q == 'seldom' }
        end

        it 'accepts environment specific config' do
          @cli.parse(%w[sidekiq -e staging -C ./test/config_environment.yml])

          assert_equal './test/config_environment.yml', Sidekiq.options[:config_file]
          refute Sidekiq.options[:verbose]
          assert_equal './test/fake_env.rb', Sidekiq.options[:require]
          assert_equal 'staging', Sidekiq.options[:environment]
          assert_equal 50, Sidekiq.options[:concurrency]
          assert_equal 2, Sidekiq.options[:queues].count { |q| q == 'very_often' }
          assert_equal 1, Sidekiq.options[:queues].count { |q| q == 'seldom' }
        end

        describe 'when config file is empty' do
          it 'sets default options' do
            @cli.parse(%w[sidekiq -C ./test/config_empty.yml -r ./test/fake_env.rb])

            assert_equal './test/config_empty.yml', Sidekiq.options[:config_file]
            refute Sidekiq.options[:verbose]
            assert_equal './test/fake_env.rb', Sidekiq.options[:require]
            assert_nil Sidekiq.options[:environment]
            assert_equal 10, Sidekiq.options[:concurrency]
            assert_equal ['default'], Sidekiq.options[:queues]
          end
        end

        describe 'when config file and flags' do
          it 'merges options' do
            @cli.parse(%w[sidekiq -C ./test/config.yml
                                  -e snoop
                                  -c 100
                                  -r ./test/fake_env.rb
                                  -q often,7
                                  -q seldom,3])

            assert_equal './test/config.yml', Sidekiq.options[:config_file]
            refute Sidekiq.options[:verbose]
            assert_equal './test/fake_env.rb', Sidekiq.options[:require]
            assert_equal 'snoop', Sidekiq.options[:environment]
            assert_equal 100, Sidekiq.options[:concurrency]
            assert_equal 7, Sidekiq.options[:queues].count { |q| q == 'often' }
            assert_equal 3, Sidekiq.options[:queues].count { |q| q == 'seldom' }
          end
        end

        describe 'default config file' do
          describe 'when required path is a directory' do
            it 'tries config/sidekiq.yml' do
              @cli.parse(%w[sidekiq -r ./test/dummy])

              assert_equal 'sidekiq.yml', File.basename(Sidekiq.options[:config_file])
              assert_equal 25, Sidekiq.options[:concurrency]
            end
          end
        end
      end
    end

    describe 'validation' do
      describe 'when required application path does not exist' do
        it 'exits with status 1' do
          exit = assert_raises(SystemExit) { @cli.parse(%w[sidekiq -r /non/existent/path]) }
          assert_equal 1, exit.status
        end
      end

      describe 'when required path is a directory without config/application.rb' do
        it 'exits with status 1' do
          exit = assert_raises(SystemExit) { @cli.parse(%w[sidekiq -r ./test/fixtures]) }
          assert_equal 1, exit.status
        end

        describe 'when config file path does not exist' do
          it 'raises argument error' do
            assert_raises(ArgumentError) do
              @cli.parse(%w[sidekiq -r ./test/fake_env.rb -C /non/existent/path])
            end
          end
        end
      end
    end
  end

  describe '#run' do
    before do
      Sidekiq.options = Sidekiq::DEFAULTS.dup
      Sidekiq.options[:require] = './test/fake_env.rb'
      @logger = Sidekiq.logger
      @logdev = StringIO.new
      Sidekiq.logger = Logger.new(@logdev)
      @cli = Sidekiq::CLI.new
    end

    after do
      Sidekiq.logger = @logger
    end

    describe 'require workers' do
      describe 'when path is a rails directory' do
        before do
          Sidekiq.options[:require] = './test/dummy'
          @cli.environment = 'test'
        end

        it 'requires sidekiq railtie and rails application with environment' do
          @cli.stub(:launch, nil) do
            @cli.run
          end

          assert defined?(Sidekiq::Rails)
          assert defined?(Dummy::Application)
        end

        it 'tags with the app directory name' do
          @cli.stub(:launch, nil) do
            @cli.run
          end

          assert_equal 'dummy', Sidekiq.options[:tag]
        end
      end

      describe 'when path is file' do
        it 'requires application' do
          @cli.stub(:launch, nil) do
            @cli.run
          end

          assert $LOADED_FEATURES.any? { |x| x =~ /test\/fake_env/ }
        end
      end
    end

    describe 'when development environment and stdout tty' do
      it 'prints banner' do
        @cli.stub(:environment, 'development') do
          assert_output(/#{Regexp.escape(Sidekiq::CLI.banner)}/) do
            $stdout.stub(:tty?, true) do
              @cli.stub(:launch, nil) do
                @cli.run
              end
            end
          end
        end
      end
    end
  end

  describe 'signal handling' do
    before do
      @cli = Sidekiq::CLI.new
      Sidekiq.options = Sidekiq::DEFAULTS.dup
      @logger = Sidekiq.logger
      @logdev = StringIO.new
      Sidekiq.logger = Logger.new(@logdev)
    end

    after do
      Sidekiq.logger = @logger
    end

    %w(INT TERM).each do |sig|
      describe sig do
        it 'raises interrupt error' do
          assert_raises Interrupt do
            @cli.handle_signal(sig)
          end
        end
      end
    end

    %w(TSTP USR1).each do |sig|
      describe sig do
        it 'quiets with a corresponding event' do
          quiet = false

          Sidekiq.on(:quiet) do
            quiet = true
          end

          @cli.parse(%w[sidekiq -r ./test/fake_env.rb])
          @cli.launcher = Sidekiq::Launcher.new(Sidekiq.options)
          @cli.handle_signal(sig)

          assert_match(/Got #{sig} signal/, @logdev.string)
          assert_equal true, quiet
        end
      end
    end

    describe 'TTIN' do
      it 'prints backtraces for all threads in the process to the logfile' do
        @cli.parse(%w[sidekiq -r ./test/fake_env.rb])
        @cli.handle_signal('TTIN')

        assert_match(/Got TTIN signal/, @logdev.string)
        assert_match(/\bbacktrace\b/, @logdev.string)
      end
    end

    describe 'UNKNOWN' do
      it 'logs about' do
        @cli.parse(%w[sidekiq -r ./test/fake_env.rb])
        @cli.handle_signal('UNKNOWN')

        assert_match(/Got UNKNOWN signal/, @logdev.string)
        assert_match(/No signal handler for UNKNOWN/, @logdev.string)
      end
    end
  end
end
