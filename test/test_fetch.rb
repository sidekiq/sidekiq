require_relative 'helper'
require 'sidekiq/fetch'

class TestFetcher < Sidekiq::Test
  describe 'fetcher' do
    before do
      Sidekiq.redis = { :url => REDIS_URL, :namespace => 'fuzzy' }
      Sidekiq.redis do |conn|
        conn.flushdb
        conn.rpush('queue:basic', 'msg')
      end
    end

    after do
      Sidekiq.redis = REDIS
    end

    it 'retrieves' do
      fetch = Sidekiq::BasicFetch.new(:queues => ['basic', 'bar'])
      uow = fetch.retrieve_work
      refute_nil uow
      assert_equal 'basic', uow.queue_name
      assert_equal 'msg', uow.message
      q = Sidekiq::Queue.new('basic')
      assert_equal 0, q.size
      uow.requeue
      assert_equal 1, q.size
      assert_nil uow.acknowledge
    end

    it 'retrieves with strict setting' do
      fetch = Sidekiq::BasicFetch.new(:queues => ['basic', 'bar', 'bar'], :strict => true)
      cmd = fetch.queues_cmd
      assert_equal cmd, ['queue:basic', 'queue:bar', 1]
    end

    it 'bulk requeues' do
      q1 = Sidekiq::Queue.new('foo')
      q2 = Sidekiq::Queue.new('bar')
      assert_equal 0, q1.size
      assert_equal 0, q2.size
      uow = Sidekiq::BasicFetch::UnitOfWork
      Sidekiq::BasicFetch.bulk_requeue([uow.new('fuzzy:queue:foo', 'bob'), uow.new('fuzzy:queue:foo', 'bar'), uow.new('fuzzy:queue:bar', 'widget')], {:queues => []})
      assert_equal 2, q1.size
      assert_equal 1, q2.size
    end

    describe 'fetching' do
      before do
        Sidekiq::Fetcher.reset
      end

      it 'instantiates' do
        begin
          Sidekiq.options[:fetch] = NullFetch
          mgr = Minitest::Mock.new
          fetch = Sidekiq::Fetcher.new(mgr, {})
          fetch.fetch
          Sidekiq::Fetcher.done!
        ensure
          Sidekiq.options[:fetch] = Sidekiq::BasicFetch
        end
      end

      class NullFetch
        def initialize(opts)
        end
        def retrieve_work
        end
        def self.bulk_requeue(*args)
        end
      end

      it 'handles redis network errors' do
        begin
          Sidekiq.logger.level = Logger::FATAL
          Sidekiq.options[:fetch] = ErrorFetch
          mgr = Minitest::Mock.new
          fetch = Sidekiq::Fetcher.new(mgr, {})
          def fetch.pause
          end
          refute fetch.down
          fetch.fetch
          Sidekiq::Fetcher.done!
          assert fetch.down
        ensure
          Sidekiq.options[:fetch] = Sidekiq::BasicFetch
          Sidekiq.logger.level = Logger::ERROR
        end
      end

      class ErrorFetch
        def initialize(opts)
        end
        def retrieve_work
          raise IOError, "ker-BOOM"
        end
        def self.bulk_requeue(*args)
        end
      end
    end

  end
end
