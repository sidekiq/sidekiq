# frozen_string_literal: true

require_relative 'helper'
require 'sidekiq/launcher'

class TestLauncher < Minitest::Test
  describe Sidekiq::Launcher do
    subject { Sidekiq::Launcher.new(options) }

    let(:options) do
      {
        concurrency: 3,
        queues: ['default'],
        tag: 'myapp'
      }
    end

    before do
      Sidekiq.redis { |c| c.flushdb }
      Sidekiq::Processor::WORKER_STATE.set('tid', { queue: 'queue', payload: 'job_hash', run_at: Time.now.to_i })
      @proctitle = $0
    end

    after do
      Sidekiq::Processor::WORKER_STATE.clear
      $0 = @proctitle
    end

    describe '#heartbeat' do
      describe 'run' do
        it 'sets sidekiq version, tag and the number of busy workers to proctitle' do
          subject.heartbeat

          assert_equal "sidekiq #{Sidekiq::VERSION} myapp [1 of 3 busy]", $0
        end

        it 'stores process info in redis' do
          subject.heartbeat

          workers = Sidekiq.redis { |c| c.hmget(subject.identity, 'busy') }

          assert_equal ["1"], workers

          expires = Sidekiq.redis { |c| c.pttl(subject.identity) }

          assert_in_delta 60000, expires, 500
        end

        describe 'events' do
          before do
            @cnt = 0

            Sidekiq.on(:heartbeat) do
              @cnt += 1
            end
          end

          it 'fires start heartbeat event only once' do
            assert_equal 0, @cnt

            subject.heartbeat

            assert_equal 1, @cnt

            subject.heartbeat

            assert_equal 1, @cnt
          end
        end
      end

      describe 'quite' do
        before do
          subject.quiet
        end

        it 'sets stopping proctitle' do
          subject.heartbeat

          assert_equal "sidekiq #{Sidekiq::VERSION} myapp [1 of 3 busy] stopping", $0
        end

        it 'stores process info in redis' do
          subject.heartbeat

          info = Sidekiq.redis { |c| c.hmget(subject.identity, 'busy') }

          assert_equal ["1"], info

          expires = Sidekiq.redis { |c| c.pttl(subject.identity) }

          assert_in_delta 60000, expires, 50
        end
      end
    end
  end
end
