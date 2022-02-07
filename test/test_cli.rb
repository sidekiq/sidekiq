# frozen_string_literal: true

require_relative 'helper'
require 'sidekiq/cli'

describe Sidekiq::CLI do
  describe '#parse' do
    before do
      Sidekiq.options = Sidekiq::DEFAULTS.dup
      @logger = Sidekiq.logger
      @logdev = StringIO.new
      Sidekiq.logger = Logger.new(@logdev)
    end

    after do
      Sidekiq.logger = @logger
    end

    subject { Sidekiq::CLI.new }

    def logdev
      @logdev ||= StringIO.new
    end

    describe '#parse' do
      describe 'options' do
        describe 'require' do
          it 'accepts with -r' do
            subject.parse(%w[sidekiq -r ./test/fake_env.rb])

            assert_equal './test/fake_env.rb', Sidekiq.options[:require]
          end
        end

        describe 'concurrency' do
          it 'accepts with -c' do
            subject.parse(%w[sidekiq -c 60 -r ./test/fake_env.rb])

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
              subject.parse(%w[sidekiq -r ./test/fake_env.rb])

              assert_equal 9, Sidekiq.options[:concurrency]
            end

            it 'option overrides RAILS_MAX_THREADS env var' do
              subject.parse(%w[sidekiq -c 60 -r ./test/fake_env.rb])

              assert_equal 60, Sidekiq.options[:concurrency]
            end
          end
        end

        describe 'setting internal options via the config file' do
          describe 'setting the `strict` option via the config file' do
            it 'discards the `strict` option specified via the config file' do
              subject.parse(%w[sidekiq -C ./test/config_with_internal_options.yml])

              assert_equal true, !!Sidekiq.options[:strict]
            end
          end
        end

        describe 'queues' do
          it 'accepts with -q' do
            subject.parse(%w[sidekiq -q foo -r ./test/fake_env.rb])

            assert_equal ['foo'], Sidekiq.options[:queues]
          end

          describe 'when weights are not present' do
            it 'accepts queues without weights' do
              subject.parse(%w[sidekiq -q foo -q bar -r ./test/fake_env.rb])

              assert_equal ['foo', 'bar'], Sidekiq.options[:queues]
            end

            it 'sets strictly ordered queues' do
              subject.parse(%w[sidekiq -q foo -q bar -r ./test/fake_env.rb])

              assert_equal true, !!Sidekiq.options[:strict]
            end
          end

          describe 'when weights are present' do
            it 'accepts queues with weights' do
              subject.parse(%w[sidekiq -q foo,3 -q bar -r ./test/fake_env.rb])

              assert_equal ['foo', 'foo', 'foo', 'bar'], Sidekiq.options[:queues]
            end

            it 'does not set strictly ordered queues' do
              subject.parse(%w[sidekiq -q foo,3 -q bar -r ./test/fake_env.rb])

              assert_equal false, !!Sidekiq.options[:strict]
            end
          end

          it 'accepts queues with multi-word names' do
            subject.parse(%w[sidekiq -q queue_one -q queue-two -r ./test/fake_env.rb])

            assert_equal ['queue_one', 'queue-two'], Sidekiq.options[:queues]
          end

          it 'accepts queues with dots in the name' do
            subject.parse(%w[sidekiq -q foo.bar -r ./test/fake_env.rb])

            assert_equal ['foo.bar'], Sidekiq.options[:queues]
          end

          describe 'when duplicate queue names' do
            it 'raises an argument error' do
              assert_raises(ArgumentError) { subject.parse(%w[sidekiq -q foo -q foo -r ./test/fake_env.rb]) }
              assert_raises(ArgumentError) { subject.parse(%w[sidekiq -q foo,3 -q foo,1 -r ./test/fake_env.rb]) }
            end
          end

          describe 'when queues are empty' do
            describe 'when no queues are specified via -q' do
              it "sets 'default' queue" do
                subject.parse(%w[sidekiq -r ./test/fake_env.rb])

                assert_equal ['default'], Sidekiq.options[:queues]
              end
            end

            describe 'when no queues are specified via the config file' do
              it "sets 'default' queue" do
                subject.parse(%w[sidekiq -C ./test/config_empty.yml -r ./test/fake_env.rb])

                assert_equal ['default'], Sidekiq.options[:queues]
              end
            end
          end
        end

        describe 'timeout' do
          it 'accepts with -t' do
            subject.parse(%w[sidekiq -t 30 -r ./test/fake_env.rb])

            assert_equal 30, Sidekiq.options[:timeout]
          end
        end

        describe 'verbose' do
          it 'accepts with -v' do
            subject.parse(%w[sidekiq -v -r ./test/fake_env.rb])

            assert_equal Logger::DEBUG, Sidekiq.logger.level
          end
        end

        describe 'config file' do
          it 'accepts with -C' do
            subject.parse(%w[sidekiq -C ./test/config.yml])

            assert_equal './test/config.yml', Sidekiq.options[:config_file]
            refute Sidekiq.options[:verbose]
            assert_equal './test/fake_env.rb', Sidekiq.options[:require]
            assert_nil Sidekiq.options[:environment]
            assert_equal 50, Sidekiq.options[:concurrency]
            assert_equal 2, Sidekiq.options[:queues].count { |q| q == 'very_often' }
            assert_equal 1, Sidekiq.options[:queues].count { |q| q == 'seldom' }
          end

          it 'accepts stringy keys' do
            subject.parse(%w[sidekiq -C ./test/config_string.yml])

            assert_equal './test/config_string.yml', Sidekiq.options[:config_file]
            refute Sidekiq.options[:verbose]
            assert_equal './test/fake_env.rb', Sidekiq.options[:require]
            assert_nil Sidekiq.options[:environment]
            assert_equal 50, Sidekiq.options[:concurrency]
            assert_equal 2, Sidekiq.options[:queues].count { |q| q == 'very_often' }
            assert_equal 1, Sidekiq.options[:queues].count { |q| q == 'seldom' }
          end

          it 'accepts environment specific config' do
            subject.parse(%w[sidekiq -e staging -C ./test/config_environment.yml])

            assert_equal './test/config_environment.yml', Sidekiq.options[:config_file]
            refute Sidekiq.options[:verbose]
            assert_equal './test/fake_env.rb', Sidekiq.options[:require]
            assert_equal 'staging', Sidekiq.options[:environment]
            assert_equal 50, Sidekiq.options[:concurrency]
            assert_equal 2, Sidekiq.options[:queues].count { |q| q == 'very_often' }
            assert_equal 1, Sidekiq.options[:queues].count { |q| q == 'seldom' }
          end

          it 'accepts environment specific config with alias' do
            subject.parse(%w[sidekiq -e staging -C ./test/config_with_alias.yml])
            assert_equal './test/config_with_alias.yml', Sidekiq.options[:config_file]
            refute Sidekiq.options[:verbose]
            assert_equal './test/fake_env.rb', Sidekiq.options[:require]
            assert_equal 'staging', Sidekiq.options[:environment]
            assert_equal 50, Sidekiq.options[:concurrency]
            assert_equal 2, Sidekiq.options[:queues].count { |q| q == 'very_often' }
            assert_equal 1, Sidekiq.options[:queues].count { |q| q == 'seldom' }

            subject.parse(%w[sidekiq -e production -C ./test/config_with_alias.yml])
            assert_equal './test/config_with_alias.yml', Sidekiq.options[:config_file]
            assert Sidekiq.options[:verbose]
            assert_equal './test/fake_env.rb', Sidekiq.options[:require]
            assert_equal 'production', Sidekiq.options[:environment]
            assert_equal 50, Sidekiq.options[:concurrency]
            assert_equal 2, Sidekiq.options[:queues].count { |q| q == 'very_often' }
            assert_equal 1, Sidekiq.options[:queues].count { |q| q == 'seldom' }
          end

          it 'exposes ERB expected __FILE__ and __dir__' do
            given_path = './test/config__FILE__and__dir__.yml'
            expected_file = File.expand_path(given_path)
            # As per Ruby's Kernel module docs, __dir__ is equivalent to File.dirname(File.realpath(__FILE__))
            expected_dir = File.dirname(File.realpath(expected_file))

            subject.parse(%W[sidekiq -C #{given_path}])

            assert_equal(expected_file, Sidekiq.options.fetch(:__FILE__))
            assert_equal(expected_dir, Sidekiq.options.fetch(:__dir__))
          end
        end

        describe 'default config file' do
          describe 'when required path is a directory' do
            it 'tries config/sidekiq.yml from required diretory' do
              subject.parse(%w[sidekiq -r ./test/dummy])

              assert_equal './test/dummy/config/sidekiq.yml', Sidekiq.options[:config_file]
              assert_equal 25, Sidekiq.options[:concurrency]
            end
          end

          describe 'when required path is a file' do
            it 'tries config/sidekiq.yml from current diretory' do
              Sidekiq.options[:require] = './test/dummy' # stub current dir – ./

              subject.parse(%w[sidekiq -r ./test/fake_env.rb])

              assert_equal './test/dummy/config/sidekiq.yml', Sidekiq.options[:config_file]
              assert_equal 25, Sidekiq.options[:concurrency]
            end
          end

          describe 'without any required path' do
            it 'tries config/sidekiq.yml from current diretory' do
              Sidekiq.options[:require] = './test/dummy' # stub current dir – ./

              subject.parse(%w[sidekiq])

              assert_equal './test/dummy/config/sidekiq.yml', Sidekiq.options[:config_file]
              assert_equal 25, Sidekiq.options[:concurrency]
            end
          end

          describe 'when config file and flags' do
            it 'merges options' do
              subject.parse(%w[sidekiq -C ./test/config.yml
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

            describe 'when the config file specifies queues with weights' do
              describe 'when -q specifies queues without weights' do
                it 'sets strictly ordered queues' do
                  subject.parse(%w[sidekiq -C ./test/config.yml
                                        -r ./test/fake_env.rb
                                        -q foo -q bar])

                  assert_equal true, !!Sidekiq.options[:strict]
                end
              end

              describe 'when -q specifies no queues' do
                it 'does not set strictly ordered queues' do
                  subject.parse(%w[sidekiq -C ./test/config.yml
                                        -r ./test/fake_env.rb])

                  assert_equal false, !!Sidekiq.options[:strict]
                end
              end

              describe 'when -q specifies queues with weights' do
                it 'does not set strictly ordered queues' do
                  subject.parse(%w[sidekiq -C ./test/config.yml
                                        -r ./test/fake_env.rb
                                        -q foo,2 -q bar,3])

                  assert_equal false, !!Sidekiq.options[:strict]
                end
              end
            end

            describe 'when the config file specifies queues without weights' do
              describe 'when -q specifies queues without weights' do
                it 'sets strictly ordered queues' do
                  subject.parse(%w[sidekiq -C ./test/config_queues_without_weights.yml
                                        -r ./test/fake_env.rb
                                        -q foo -q bar])

                  assert_equal true, !!Sidekiq.options[:strict]
                end
              end

              describe 'when -q specifies no queues' do
                it 'sets strictly ordered queues' do
                  subject.parse(%w[sidekiq -C ./test/config_queues_without_weights.yml
                                        -r ./test/fake_env.rb])

                  assert_equal true, !!Sidekiq.options[:strict]
                end
              end

              describe 'when -q specifies queues with weights' do
                it 'does not set strictly ordered queues' do
                  subject.parse(%w[sidekiq -C ./test/config_queues_without_weights.yml
                                        -r ./test/fake_env.rb
                                        -q foo,2 -q bar,3])

                  assert_equal false, !!Sidekiq.options[:strict]
                end
              end
            end

            describe 'when the config file specifies no queues' do
              describe 'when -q specifies queues without weights' do
                it 'sets strictly ordered queues' do
                  subject.parse(%w[sidekiq -C ./test/config_empty.yml
                                        -r ./test/fake_env.rb
                                        -q foo -q bar])

                  assert_equal true, !!Sidekiq.options[:strict]
                end
              end

              describe 'when -q specifies no queues' do
                it 'sets strictly ordered queues' do
                  subject.parse(%w[sidekiq -C ./test/config_empty.yml
                                        -r ./test/fake_env.rb])

                  assert_equal true, !!Sidekiq.options[:strict]
                end
              end

              describe 'when -q specifies queues with weights' do
                it 'does not set strictly ordered queues' do
                  subject.parse(%w[sidekiq -C ./test/config_empty.yml
                                        -r ./test/fake_env.rb
                                        -q foo,2 -q bar,3])

                  assert_equal false, !!Sidekiq.options[:strict]
                end
              end
            end
          end

          describe 'default config file' do
            describe 'when required path is a directory' do
              it 'tries config/sidekiq.yml' do
                subject.parse(%w[sidekiq -r ./test/dummy])

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
            exit = assert_raises(SystemExit) { subject.parse(%w[sidekiq -r /non/existent/path]) }
            assert_equal 1, exit.status
          end
        end

        describe 'when required path is a directory without config/application.rb' do
          it 'exits with status 1' do
            exit = assert_raises(SystemExit) { subject.parse(%w[sidekiq -r ./test/fixtures]) }
            assert_equal 1, exit.status
          end

          describe 'when config file path does not exist' do
            it 'raises argument error' do
              assert_raises(ArgumentError) do
                subject.parse(%w[sidekiq -r ./test/fake_env.rb -C /non/existent/path])
              end
            end
          end
        end

        describe 'when concurrency is not valid' do
          describe 'when set to 0' do
            it 'raises argument error' do
              assert_raises(ArgumentError) do
                subject.parse(%w[sidekiq -r ./test/fake_env.rb -c 0])
              end
            end
          end

          describe 'when set to a negative number' do
            it 'raises argument error' do
              assert_raises(ArgumentError) do
                subject.parse(%w[sidekiq -r ./test/fake_env.rb -c -2])
              end
            end
          end
        end

        describe 'when timeout is not valid' do
          describe 'when set to 0' do
            it 'raises argument error' do
              assert_raises(ArgumentError) do
                subject.parse(%w[sidekiq -r ./test/fake_env.rb -t 0])
              end
            end
          end

          describe 'when set to a negative number' do
            it 'raises argument error' do
              assert_raises(ArgumentError) do
                subject.parse(%w[sidekiq -r ./test/fake_env.rb -t -2])
              end
            end
          end
        end
      end
    end

    describe '#run' do
      before do
        Sidekiq.options[:concurrency] = 2
        Sidekiq.options[:require] = './test/fake_env.rb'
      end

      describe 'require workers' do
        describe 'when path is a rails directory' do
          before do
            Sidekiq.options[:require] = './test/dummy'
            subject.environment = 'test'
          end

          it 'requires sidekiq railtie and rails application with environment' do
            subject.stub(:launch, nil) do
              subject.run
            end

            assert defined?(Sidekiq::Rails)
            assert defined?(Dummy::Application)
          end

          it 'tags with the app directory name' do
            subject.stub(:launch, nil) do
              subject.run
            end

            assert_equal 'dummy', Sidekiq.options[:tag]
          end
        end

        describe 'when path is file' do
          it 'requires application' do
            subject.stub(:launch, nil) do
              subject.run
            end

            assert $LOADED_FEATURES.any? { |x| x =~ /test\/fake_env/ }
          end
        end
      end

      describe 'when development environment and stdout tty' do
        it 'prints banner' do
          subject.stub(:environment, 'development') do
            assert_output(/#{Regexp.escape(Sidekiq::CLI.banner)}/) do
              $stdout.stub(:tty?, true) do
                subject.stub(:launch, nil) do
                  subject.run
                end
              end
            end
          end
        end
      end

      it 'prints rails info' do
        subject.stub(:environment, 'production') do
          subject.stub(:launch, nil) do
            subject.run
          end
          assert_includes @logdev.string, "Booted Rails #{::Rails.version} application in production environment"
        end
      end

      describe 'checking maxmemory policy' do
        it 'warns if the policy is not noeviction' do
          redis_info = { "maxmemory_policy" => "allkeys-lru", "redis_version" => "6" }

          Sidekiq.stub(:redis_info, redis_info) do
            subject.stub(:launch, nil) do
              subject.run
            end
          end

          assert_includes @logdev.string, "allkeys-lru"
        end

        it 'silent if the policy is noeviction' do
          redis_info = { "maxmemory_policy" => "noeviction", "redis_version" => "6" }

          Sidekiq.stub(:redis_info, redis_info) do
            subject.stub(:launch, nil) do
              subject.run
            end
          end

          refute_includes @logdev.string, "noeviction"
        end
      end
    end

    describe 'signal handling' do
      %w(INT TERM).each do |sig|
        describe sig do
          it 'raises interrupt error' do
            assert_raises Interrupt do
              subject.handle_signal(sig)
            end
          end
        end
      end

      describe "TSTP" do
        it 'quiets with a corresponding event' do
          quiet = false

          Sidekiq.on(:quiet) do
            quiet = true
          end

          subject.launcher = Sidekiq::Launcher.new(Sidekiq.options)
          subject.handle_signal("TSTP")

          assert_match(/Got TSTP signal/, logdev.string)
          assert_equal true, quiet
        end
      end

      describe 'TTIN' do
        it 'prints backtraces for all threads in the process to the logfile' do
          subject.handle_signal('TTIN')

          assert_match(/Got TTIN signal/, logdev.string)
          assert_match(/\bbacktrace\b/, logdev.string)
        end
      end

      describe 'UNKNOWN' do
        it 'logs about' do
          # subject.parse(%w[sidekiq -r ./test/fake_env.rb])
          subject.handle_signal('UNKNOWN')

          assert_match(/Got UNKNOWN signal/, logdev.string)
          assert_match(/No signal handler registered/, logdev.string)
        end
      end
    end
  end
end
