# frozen_string_literal: true

require_relative 'helper'
require 'sidekiq/logging'

class TestLogging < Minitest::Test
  describe Sidekiq::Logging do
    after do
      Thread.current[:sidekiq_context] = nil
    end

    describe '.context' do
      subject { Sidekiq::Logging.context }

      describe 'default' do
        it 'returns empty array' do
          assert_equal [], subject
        end
      end

      describe 'memoization' do
        before do
          Thread.current[:sidekiq_context] = 'context'
        end

        it 'returns current thread :sidekiq_context attribute reference' do
          assert_equal 'context', subject
        end
      end
    end

    describe ".with_context" do
      subject { Sidekiq::Logging.context }

      it "adds context to the current thread" do
        Sidekiq::Logging.with_context('A') do
          assert_includes subject, 'A'
        end

        assert_empty subject
      end

      describe 'nested contexts' do
        it "adds multiple contexts to the current thread" do
          Sidekiq::Logging.with_context('A') do
            assert_equal ['A'], subject
            Sidekiq::Logging.with_context('B') do
              assert_equal ['A', 'B'], subject
            end
            assert_equal ['A'], subject
          end
          assert_empty subject
        end
      end
    end

    describe 'formatters' do
      let(:severity) { 'INFO' }
      let(:utc_time) { Time.utc(2020, 1, 1) }
      let(:prg) { 'sidekiq' }
      let(:msg) { 'Old pond frog jumps in sound of water' }

      around do |test|
        Process.stub :pid, 4710 do
          Sidekiq::Logging.stub :tid, 'ouy7z76mx' do
            test.call
          end
        end
      end

      describe Sidekiq::Logging::Pretty do
        describe '#call' do
          subject { Sidekiq::Logging::Pretty.new.call(severity, utc_time, prg, msg) }

          it 'formats with timestamp, pid, tid, severity, message' do
            assert_equal "2020-01-01T00:00:00.000Z 4710 TID-ouy7z76mx INFO: Old pond frog jumps in sound of water\n", subject
          end

          describe 'with context' do
            around do |test|
              Sidekiq::Logging.stub :context, ['HaikuWorker', 'JID-dac39c70844dc0ee3f157ced'] do
                test.call
              end
            end

            it 'formats with timestamp, pid, tid, context, severity, message' do
              assert_equal "2020-01-01T00:00:00.000Z 4710 TID-ouy7z76mx HaikuWorker JID-dac39c70844dc0ee3f157ced INFO: Old pond frog jumps in sound of water\n", subject
            end
          end
        end
      end

      describe Sidekiq::Logging::WithoutTimestamp do
        describe '#call' do
          subject { Sidekiq::Logging::WithoutTimestamp.new.call(severity, utc_time, prg, msg) }

          it 'formats with pid, tid, severity, message' do
            assert_equal "4710 TID-ouy7z76mx INFO: Old pond frog jumps in sound of water\n", subject
          end

          describe 'with context' do
            around do |test|
              Sidekiq::Logging.stub :context, ['HaikuWorker', 'JID-dac39c70844dc0ee3f157ced'] do
                test.call
              end
            end

            it 'formats with pid, tid, context, severity, message' do
              assert_equal "4710 TID-ouy7z76mx HaikuWorker JID-dac39c70844dc0ee3f157ced INFO: Old pond frog jumps in sound of water\n", subject
            end
          end
        end
      end
          end
        end
      end
    end
  end
end
