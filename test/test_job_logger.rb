# frozen_string_literal: true

require_relative 'helper'
require 'sidekiq/job_logger'

class TestJobLogger < Minitest::Test
  describe Sidekiq::JobLogger do
    subject { Sidekiq::JobLogger.new }

    let(:logdev) { StringIO.new }

    around do |test|
      Sidekiq.stub :logger, Sidekiq::Logging.initialize_logger(logdev) do
        Process.stub :pid, 4710 do
          Sidekiq::Logging.stub :tid, 'ouy7z76mx' do
            Time.stub :now, Time.utc(2020, 1, 1) do
              test.call
            end
          end
        end
      end
    end

    after do
      Thread.current[:sidekiq_context] = nil
    end

    describe '#call' do
      describe 'when pretty formatter' do
        before do
          Sidekiq.logger.formatter = Sidekiq::Logging::Pretty.new
        end

        it 'logs elapsed time as context' do
          subject.call('item', 'queue') {}

          assert_match(/2020-01-01T00:00:00\.000Z 4710 TID-ouy7z76mx INFO: start/, logdev.string)
          assert_match(/2020-01-01T00:00:00\.000Z 4710 TID-ouy7z76mx elapsed: .+ sec INFO: done/, logdev.string)
        end
      end

      describe 'when json formatter' do
        before do
          Sidekiq.logger.formatter = Sidekiq::Logging::JSON.new
        end

        it 'logs elapsed time as context' do
          subject.call('item', 'queue') {}

          assert_match(/{.+context.+\[\].+message.+start.+}/, logdev.string)
          assert_match(/{.+context.+\[.+elapsed:.+sec.+\].+message.+done.+}/, logdev.string)
        end
      end
    end
  end
end
