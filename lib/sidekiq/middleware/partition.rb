# frozen_string_literal: true

module Sidekiq
  module Middleware
    # Partitioned queue processing. Jobs that share a partition key run one at a time, in the order
    # they were enqueued (FIFO within a partition), while jobs with different keys run concurrently
    # across the queue's threads. Point the middleware at the argument that holds the key:
    #
    #     class LedgerJob
    #       include Sidekiq::Job
    #       sidekiq_options partition: 0   # args[0] is the partition key (e.g. an account id)
    #
    #       def perform(account_id, amount)
    #         # jobs for the same account_id never run at the same time
    #       end
    #     end
    #
    # A job whose partition is already busy is rescheduled a few seconds later instead of blocking a
    # worker thread, so the other partitions keep flowing. Enable it on the server:
    #
    #     Sidekiq.configure_server do |config|
    #       config.server_middleware do |chain|
    #         chain.add Sidekiq::Middleware::Partition::Server
    #       end
    #     end
    #
    # Per-worker overrides (all optional):
    #   sidekiq_options partition: 0            # which arg is the key; nil disables partitioning
    #   sidekiq_options partition_ttl: 3600     # lock lifetime, must exceed the job's max runtime
    #   sidekiq_options partition_requeue_in: 5 # seconds to wait before re-checking a busy partition
    module Partition
      class Server
        include Sidekiq::ServerMiddleware

        # The lock must outlive the longest a partitioned job can run: if it expired mid-job a second
        # job for the same key could start. Bounded so a crashed worker can't wedge a partition forever.
        DEFAULT_TTL = 3600
        # How long a job waits before its partition is re-checked.
        DEFAULT_REQUEUE_IN = 5

        # Release the lock only while we still hold it — an expired lock may already belong to the
        # next job, and we must not delete theirs.
        RELEASE = <<~LUA
          if redis.call("get", KEYS[1]) == ARGV[1] then
            return redis.call("del", KEYS[1])
          end
          return 0
        LUA

        def call(worker, job, queue)
          options = worker.class.get_sidekiq_options
          key = partition_key(job, options["partition"])
          return yield if key.nil?

          lock = "partition:#{queue}:#{key}"
          if acquire(lock, job["jid"], (options["partition_ttl"] || DEFAULT_TTL).to_i)
            begin
              yield
            ensure
              release(lock, job["jid"])
            end
          else
            requeue(job, (options["partition_requeue_in"] || DEFAULT_REQUEUE_IN).to_f)
          end
        end

        private

        def partition_key(job, index)
          return nil if index.nil?

          Array(job["args"])[index]
        end

        def acquire(lock, jid, ttl)
          redis { |conn| conn.call("SET", lock, jid, "NX", "EX", ttl) } == "OK"
        end

        def release(lock, jid)
          redis { |conn| conn.call("EVAL", RELEASE, 1, lock, jid) }
        rescue => ex
          # A leaked lock only self-heals at its TTL, but failing here must not fail the job.
          logger.warn { "Partition: could not release #{lock}: #{ex.message}" }
        end

        # Defer the job onto the scheduled set; the scheduler enqueues it back to its queue when due,
        # so no thread is held while the partition is busy. Earlier-deferred jobs get an earlier time,
        # which keeps a busy partition draining roughly in enqueue order.
        def requeue(job, delay)
          payload = job.merge("partition_requeues" => (job["partition_requeues"] || 0) + 1)
          redis { |conn| conn.zadd("schedule", (Time.now.to_f + delay).to_s, Sidekiq.dump_json(payload)) }
          logger.debug { "Partition busy, rescheduled #{job["class"]} (jid=#{job["jid"]}) in #{delay}s" }
        end
      end
    end
  end
end
